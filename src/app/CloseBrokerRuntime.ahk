#Include PanelWindowTracker.ahk
global CloseActionSink := 0, CloseAcceptanceLog := ""
global BrokerRequestSink := 0
global PendingBrokerGeneration := 0
global CloseLastResult := "not_requested", CloseLastRequested := "", CloseLatencyMs := 0
global CloseBrokerHandle := 0, CloseBrokerPID := 0, CloseBrokerHWND := 0
global CloseBrokerToken := 0, CloseBrokerReady := false, CloseBrokerReadyPath := "", CloseBrokerStarted := 0
global CloseRequestSeq := 0, CloseBusy := false, CloseStartedTick := 0
MouseCloseVoice(vk, *) {
    global SettingsOpen, CloseBindingSpec, CloseActionSink
    if SettingsOpen || !IsObject(CloseBindingSpec) || CloseBindingSpec.VK != vk
        return
    if IsObject(CloseActionSink) {
        CloseActionSink.Call()
        return
    }
    StartCloseWorker()
}
StartCloseBroker() {
    global DataDir
    global CloseBrokerHandle, CloseBrokerPID, CloseBrokerHWND, CloseBrokerToken
    global CloseBrokerReady, CloseBrokerReadyPath, CloseBrokerStarted, CloseLastResult
    if CloseBrokerHandle
        return
    guid := Buffer(16), text := Buffer(80)
    if DllCall("ole32\CoCreateGuid", "Ptr", guid, "Int") != 0
        return
    DllCall("ole32\StringFromGUID2", "Ptr", guid, "Ptr", text, "Int", 40)
    id := Trim(StrGet(text), "{}")
    CloseBrokerToken := Random(1, 2147483647)
    CloseBrokerReady := false
    CloseBrokerReadyPath := DataDir "\close-broker-" id ".ready.json"
    DllCall("SetPropW", "Ptr", A_ScriptHwnd, "WStr", "WinVoiceHotkeyBrokerOwner", "Ptr", CloseBrokerToken)
    OnMessage(0x805A, CloseBrokerResult)
    try {
        Run('"' A_ScriptDir '\VoicePanelBroker.exe" --broker ' id " " DllCall("GetCurrentProcessId", "UInt") " " A_ScriptHwnd " " CloseBrokerToken, A_ScriptDir, "Hide", &CloseBrokerPID)
        CloseBrokerHandle := DllCall("OpenProcess", "UInt", 0x101001, "Int", false, "UInt", CloseBrokerPID, "Ptr")
        CloseBrokerStarted := A_TickCount
        if CloseBrokerHandle
            SetTimer(PollCloseBrokerReady, 50)
        else
            CloseLastResult := "helper_start_failed"
    } catch
        CloseLastResult := "helper_start_failed"
}
PollCloseBrokerReady(*) {
    global CloseBrokerHandle, CloseBrokerReadyPath, CloseBrokerHWND, CloseBrokerPID
    global CloseBrokerReady, CloseBrokerToken, CloseBrokerStarted, CloseLastResult
    if FileExist(CloseBrokerReadyPath) {
        try {
            json := FileRead(CloseBrokerReadyPath, "UTF-8")
            if !RegExMatch(json, '"HWND":(\d+)', &h) || !RegExMatch(json, '"Token":(\d+)', &t)
                return
            owner := 0
            DllCall("GetWindowThreadProcessId", "Ptr", h[1], "UInt*", &owner)
            if owner != CloseBrokerPID || t[1] != CloseBrokerToken
                return
            CloseBrokerHWND := h[1] + 0, CloseBrokerReady := true
            try FileDelete(CloseBrokerReadyPath)
            SetTimer(PollCloseBrokerReady, 0)
            SetTimer(WatchCloseWorker, 200)
            try WriteCloseStatus()
        }
    }
    if !CloseBrokerReady && A_TickCount - CloseBrokerStarted > 4000 {
        CloseLastResult := "helper_start_failed"
        SetTimer(PollCloseBrokerReady, 0)
    }
}
StartCloseWorker(mode := "close") {
    global CloseBusy, CloseBrokerReady, CloseBrokerHWND, CloseBrokerToken
    global CloseRequestSeq, CloseStartedTick, CloseLastRequested, CloseLastResult
    global BrokerRequestSink, PendingBrokerAction, PanelCandidateOverflow, PendingBrokerGeneration, InputState
    if mode != "close" && mode != "toggle" && mode != "presence"
        return false
    if IsObject(BrokerRequestSink) {
        BrokerRequestSink.Call(mode)
        return true
    }
    if CloseBusy
        return false
    if !CloseBrokerReady {
        CloseLastResult := "helper_not_ready"
        try WriteCloseStatus()
        return false
    }
    if !RefreshPanelCandidates() || PanelCandidateOverflow {
        CloseLastResult := "candidate_scan_incomplete"
        return false
    }
    SupportLog("panel_request", "mode=" mode " candidates=" PanelCandidates.Count)
    CloseRequestSeq += 1
    json := '{"Seq":' CloseRequestSeq ',"Action":"' mode '","Candidates":' PanelCandidateJSON() '}'
    bytes := Buffer(StrPut(json, "UTF-8"), 0)
    StrPut(json, bytes, "UTF-8")
    packet := Buffer(A_PtrSize * 3, 0)
    NumPut("Ptr", CloseBrokerToken, packet, 0)
    NumPut("UInt", bytes.Size, packet, A_PtrSize)
    NumPut("Ptr", bytes.Ptr, packet, A_PtrSize * 2)
    CloseBusy := true, CloseStartedTick := A_TickCount
    PendingBrokerAction := mode
    PendingBrokerGeneration := InputState.Generation
    CloseLastRequested := A_NowUTC, CloseLastResult := "pending"
    result := 0
    okay := DllCall("SendMessageTimeoutW", "Ptr", CloseBrokerHWND, "UInt", 0x4A,
        "Ptr", A_ScriptHwnd, "Ptr", packet, "UInt", 2, "UInt", 200, "Ptr*", &result, "Ptr")
    if !okay || result != 1 {
        CloseBusy := false
        CloseLastResult := result = 2 ? "helper_busy" : "helper_not_ready"
        try WriteCloseStatus()
        return false
    }
    return true
}
CloseBrokerResult(packed, token, *) {
    global DataDir
    global CloseBrokerToken, CloseRequestSeq, CloseBusy, CloseLastResult, CloseStartedTick
    global CloseLatencyMs, CloseAcceptanceLog, PendingBrokerAction, PendingBrokerGeneration, InputState, ActionState
    if token != CloseBrokerToken || (packed >> 8) != CloseRequestSeq
        return
    codes := Map(1, "closed", 2, "no_verified_panel", 3, "ambiguous_panel", 4, "close_not_confirmed", 5, "rejected", 6, "helper_timeout_no_other_action", 7, "panel_present", 8, "panel_absent", 9, "panel_not_ready")
    CloseLastResult := codes.Has(packed & 255) ? codes[packed & 255] : "helper_result_unknown"
    CloseLatencyMs := A_TickCount - CloseStartedTick
    CloseBusy := false
    if CloseAcceptanceLog != "" {
        try {
            json := FileRead(DataDir "\close-last-result.json", "UTF-8")
            if RegExMatch(json, '"Seq":' CloseRequestSeq '(,|})')
                FileAppend(json "`n", CloseAcceptanceLog, "UTF-8-RAW")
        }
    }
    try WriteCloseStatus()
    if IsObject(InputState) && InputState.Generation = PendingBrokerGeneration
        PanelActionCompleted(PendingBrokerAction, CloseLastResult)
    else
        ActionState.Cancel()
}
WatchCloseWorker(*) {
    global CloseBrokerHandle, CloseBrokerReady, CloseBusy, CloseStartedTick, CloseLastResult, ActionState
    if CloseBrokerHandle && DllCall("WaitForSingleObject", "Ptr", CloseBrokerHandle, "UInt", 0) = 0 {
        CloseBrokerReady := false, CloseBusy := false
        CloseLastResult := "helper_not_ready"
        SetTimer(WatchCloseWorker, 0)
        ActionState.Cancel()
        try WriteCloseStatus()
    } else if CloseBusy && A_TickCount - CloseStartedTick > 2500 {
        CloseBusy := false
        CloseLastResult := "helper_timeout_no_other_action"
        ActionState.Cancel()
    }
}
StopCloseWorker(*) {
    global CloseBrokerHandle, CloseBrokerHWND, CloseBrokerToken, CloseBrokerReady, CloseBrokerReadyPath
    SetTimer(PollCloseBrokerReady, 0)
    SetTimer(WatchCloseWorker, 0)
    CloseBrokerReady := false
    if CloseBrokerHWND
        DllCall("PostMessageW", "Ptr", CloseBrokerHWND, "UInt", 0x9001, "Ptr", A_ScriptHwnd, "Ptr", CloseBrokerToken)
    if CloseBrokerHandle {
        if DllCall("WaitForSingleObject", "Ptr", CloseBrokerHandle, "UInt", 500) != 0
            DllCall("TerminateProcess", "Ptr", CloseBrokerHandle, "UInt", 125)
        DllCall("CloseHandle", "Ptr", CloseBrokerHandle)
        CloseBrokerHandle := 0
    }
    DllCall("RemovePropW", "Ptr", A_ScriptHwnd, "WStr", "WinVoiceHotkeyBrokerOwner")
    if CloseBrokerReadyPath != "" && FileExist(CloseBrokerReadyPath)
        try FileDelete(CloseBrokerReadyPath)
}
WriteCloseStatus() {
    global DataDir
    global CloseKey, CloseLastResult, CloseLastRequested, CloseLatencyMs
    global CloseBrokerPID, CloseBrokerReady
    path := DataDir "\mapping-state.ini"
    IniWrite(CloseKey, path, "State", "CloseKey")
    IniWrite(CloseLastResult, path, "State", "CloseResult")
    IniWrite(CloseLastRequested, path, "State", "CloseRequestedUTC")
    IniWrite(CloseLatencyMs, path, "State", "CloseLatencyMs")
    IniWrite(CloseBrokerPID, path, "State", "CloseBrokerPID")
    IniWrite(CloseBrokerReady ? 1 : 0, path, "State", "CloseBrokerReady")
}
