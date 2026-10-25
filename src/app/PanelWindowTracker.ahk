; Window metadata only. No input text, microphone access or coordinate clicks.
global PanelEventHook := 0, PanelEventCallback := 0, PanelCandidates := Map()
global PanelEventTotal := 0, PanelLastObservedHWND := 0
global PanelCandidateOverflow := false
global PanelScanComplete := true
global PanelAuditBudget := 0
global PanelChildVisits := 0, PanelScanStarted := 0
RefreshPanelCandidates(recheck := 0, enumerate := 0) {
    global PanelCandidates, PanelCandidateOverflow, PanelScanComplete, PanelAuditBudget
    global PanelChildVisits, PanelScanStarted
    cached := PanelCandidates.Clone()
    PanelAuditBudget := 32
    PanelCandidates.Clear(), PanelCandidateOverflow := false, PanelScanComplete := true, PanelChildVisits := 0
    PanelScanStarted := A_TickCount
    ; WinEvent can find immersive/child frames absent from EnumWindows. Revalidate rather than discard them.
    probe := IsObject(recheck) ? recheck : ObservePanelWindowEvent
    for hwnd in cached
        probe.Call(hwnd, 0x8002)
    if IsObject(enumerate) {
        enumerate.Call()
        return PanelScanComplete && !PanelCandidateOverflow
    }
    callback := CallbackCreate(EnumPanelCandidate, "Fast", 2)
    try {
        if !DllCall("EnumWindows", "Ptr", callback, "Ptr", 0)
            PanelScanComplete := false
    }
    finally CallbackFree(callback)
    ; Seed already-visible frames after startup as well. This reads only native metadata;
    ; only exact Explorer ApplicationFrameWindow candidates reach the existing UIA verifier.
    childCallback := CallbackCreate(EnumPanelChildCandidate, "Fast", 2)
    try DllCall("EnumChildWindows", "Ptr", DllCall("GetDesktopWindow", "Ptr"), "Ptr", childCallback, "Ptr", 0)
    finally CallbackFree(childCallback)
    SupportLog("candidate_scan", "cached=" cached.Count " current=" PanelCandidates.Count
        " native_children=" PanelChildVisits " complete=" PanelScanComplete)
    return PanelScanComplete && !PanelCandidateOverflow
}
EnumPanelChildCandidate(hwnd, context) {
    global PanelChildVisits, PanelScanStarted, PanelScanComplete
    PanelChildVisits += 1
    if PanelChildVisits > 8192 || A_TickCount - PanelScanStarted > 150 {
        PanelScanComplete := false
        return false
    }
    className := Buffer(512, 0)
    if DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", className, "Int", 256)
        && StrGet(className) = "ApplicationFrameWindow"
        ObservePanelWindowEvent(hwnd, 0x8002)
    return true
}
EnumPanelCandidate(hwnd, context) {
    ObservePanelWindowEvent(hwnd, 0x8002)
    return true
}
StartPanelWindowTracker() {
    global PanelEventHook, PanelEventCallback
    if PanelEventHook
        return
    OnMessage(0x8059, ObserveTrackedPanelEvent)
    PanelEventCallback := CallbackCreate(PanelWindowEventCallback, "Fast", 7)
    PanelEventHook := DllCall("SetWinEventHook", "UInt", 0x8000, "UInt", 0x800B,
        "Ptr", 0, "Ptr", PanelEventCallback, "UInt", 0, "UInt", 0, "UInt", 2, "Ptr")
    if !PanelEventHook
        throw OSError()
}
StopPanelWindowTracker(*) {
    global PanelEventHook, PanelEventCallback, PanelCandidates
    if PanelEventHook
        DllCall("UnhookWinEvent", "Ptr", PanelEventHook)
    PanelEventHook := 0
    if PanelEventCallback
        CallbackFree(PanelEventCallback)
    PanelEventCallback := 0
    PanelCandidates.Clear()
}
PanelWindowEventCallback(hook, event, hwnd, objectID, childID, thread, time) {
    global PanelEventTotal
    PanelEventTotal += 1
    if hwnd && objectID = 0 && childID = 0
        && (event = 0x8000 || event = 0x8001 || event = 0x8002 || event = 0x8003 || event = 0x800B)
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8059, "Ptr", hwnd, "Ptr", event)
}
ObservePanelWindowEvent(hwnd, event, *) {
    global PanelCandidates, PanelLastObservedHWND, PanelCandidateOverflow, PanelScanComplete
    if event = 0x8001 || event = 0x8003 {
        if PanelCandidates.Has(hwnd) {
            PanelCandidates.Delete(hwnd)
        }
        return
    }
    try {
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            return
        className := Buffer(512, 0)
        if !DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", className, "Int", 256)
            return
        AuditNativePanelCandidate(hwnd, StrGet(className))
        if StrGet(className) != "ApplicationFrameWindow"
            return
        pid := 0
        thread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
        if StrLower(ProcessGetPath(pid)) != StrLower(A_WinDir "\Explorer.EXE")
            return
        rect := Buffer(16)
        if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
            || NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int") < 100
            || NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int") > 1024
            || NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int") < 50
            || NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int") > 768
            return
        owner := 0
        thread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &owner, "UInt")
        handle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        if !handle {
            PanelScanComplete := false
            return
        }
        times := Buffer(32)
        try okay := DllCall("GetProcessTimes", "Ptr", handle, "Ptr", times,
            "Ptr", times.Ptr + 8, "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24)
        finally DllCall("CloseHandle", "Ptr", handle)
        if !okay || owner != pid {
            PanelScanComplete := false
            return
        }
        if PanelCandidates.Count >= 16 && !PanelCandidates.Has(hwnd) {
            PanelCandidateOverflow := true
            return
        }
        PanelCandidates[hwnd] := {PID: pid, ThreadID: thread, StartFileTime: NumGet(times, 0, "Int64")}
        PanelLastObservedHWND := hwnd
    } catch {
        PanelScanComplete := false
    }
}
AuditNativePanelCandidate(hwnd, className) {
    global SupportDiagnostics, PanelAuditBudget
    if !SupportDiagnostics || PanelAuditBudget <= 0
        return
    pid := 0
    thread := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
    try path := StrLower(ProcessGetPath(pid))
    catch
        return
    explorer := path = StrLower(A_WinDir "\Explorer.EXE")
    input := path = StrLower(A_WinDir "\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\TextInputHost.exe")
    if !input && !(explorer && className = "ApplicationFrameWindow")
        return
    PanelAuditBudget -= 1
    rect := Buffer(16)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    SupportLog("native_candidate", "HWND=" hwnd " PID=" pid " Thread=" thread " Class=" className
        " Owner=" (input ? "TextInputHost" : "Explorer") " Width=" (NumGet(rect,8,"Int")-NumGet(rect,0,"Int"))
        " Height=" (NumGet(rect,12,"Int")-NumGet(rect,4,"Int")))
}
PanelCandidateJSON() {
    global PanelCandidates
    text := "[", separator := "", quote := Chr(34)
    for hwnd, c in PanelCandidates {
        text .= separator "{" quote "HWND" quote ":" hwnd "," quote "PID" quote ":" c.PID
            . "," quote "ThreadID" quote ":" c.ThreadID "," quote "StartFileTime" quote ":" c.StartFileTime "}"
        separator := ","
    }
    return text "]"
}
ObserveTrackedPanelEvent(hwnd,event,*) {
 global PanelCandidates
 known := PanelCandidates.Has(hwnd)
 ObservePanelWindowEvent(hwnd,event)
 if known || PanelCandidates.Has(hwnd)
  BrokerNativePanelChanged()
}