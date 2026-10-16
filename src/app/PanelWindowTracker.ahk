; Window metadata only. No input text, microphone access or coordinate clicks.
global PanelEventHook := 0, PanelEventCallback := 0, PanelCandidates := Map()
global PanelEventTotal := 0, PanelLastObservedHWND := 0
StartPanelWindowTracker() {
    global PanelEventHook, PanelEventCallback
    if PanelEventHook
        return
    OnMessage(0x8059, ObservePanelWindowEvent)
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
    global PanelCandidates, PanelLastObservedHWND
    if event = 0x8001 || event = 0x8003 {
        if PanelCandidates.Has(hwnd)
            PanelCandidates.Delete(hwnd)
        return
    }
    try {
        className := Buffer(512, 0)
        if !DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", className, "Int", 256)
            || StrGet(className) != "ApplicationFrameWindow"
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
        if !handle
            return
        times := Buffer(32)
        try okay := DllCall("GetProcessTimes", "Ptr", handle, "Ptr", times,
            "Ptr", times.Ptr + 8, "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24)
        finally DllCall("CloseHandle", "Ptr", handle)
        if !okay || owner != pid
            return
        if PanelCandidates.Count >= 16 && !PanelCandidates.Has(hwnd)
            return
        PanelCandidates[hwnd] := {PID: pid, ThreadID: thread, StartFileTime: NumGet(times, 0, "Int64")}
        PanelLastObservedHWND := hwnd
    }
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
