#Include MouseObserver.ahk
global KeyboardObserverHandle := 0, KeyboardObserverCallback := 0
global RecordingActive := false, RecordHeldVK := 0, RecordHeldSC := 0, RecordHeldMouse := false
global RecordHeldNative := false, RecordedCombination := false, RecordingCancelled := false
global RecordedSpec := 0, RecordExpiry := 0, RecordDisplay := 0, RecordButton := 0, RecordCaptureControl := 0
global RecordingPendingVK := 0, RecordingPendingSC := 0, RecordingPendingMouse := false
global RecordingTarget := "open", RecordingGeneration := 1

StartKeyboardObserver(*) {
    global KeyboardObserverHandle, KeyboardObserverCallback
    if KeyboardObserverHandle
        return
    KeyboardObserverCallback := CallbackCreate(KeyboardObserverProc, "Fast", 3)
    KeyboardObserverHandle := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", KeyboardObserverCallback,
        "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    if !KeyboardObserverHandle
        throw OSError()
    StartMouseObserver()
}
KeyboardObserverProc(code, message, pointer) {
    if code >= 0 {
        try {
            event := DecodeKeyboardEvent(message, pointer)
            if ObserveKeyboardMetadata(event.VK, event.SC, event.Down, event.Injected)
                return 1
        } catch {
            ; Unknown input remains native; recording is disarmed on an unexpected hook error.
            global RecordingActive
            RecordingActive := false
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "Ptr", message, "Ptr", pointer, "Ptr")
}
DecodeKeyboardEvent(message, pointer) {
    flags := NumGet(pointer, 8, "UInt"), vk := NumGet(pointer, 0, "UInt"), rawSC := NumGet(pointer, 4, "UInt")
    if vk = 0x10
        vk := (rawSC & 0xFF) = 0x36 ? 0xA1 : 0xA0
    else if vk = 0x11
        vk := flags & 1 ? 0xA3 : 0xA2
    else if vk = 0x12
        vk := flags & 1 ? 0xA5 : 0xA4
    return {VK: vk, SC: rawSC | (flags & 1 ? 0x100 : 0), Down: message = 0x100 || message = 0x104, Injected: !!(flags & 0x12)}
}
OtherPhysicalKeyDown(selectedVK) {
    Loop 247 {
        vk := A_Index + 7
        if vk = selectedVK || (vk = 0x10 && selectedVK >= 0xA0 && selectedVK <= 0xA1)
            || (vk = 0x11 && selectedVK >= 0xA2 && selectedVK <= 0xA3)
            || (vk = 0x12 && selectedVK >= 0xA4 && selectedVK <= 0xA5)
            continue
        if DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000
            return true
    }
    return false
}
ObserveKeyboardMetadata(vk, sc, down, injected) {
    global InputState, SettingsOpen, RecoveryPaused
    if !IsObject(InputState)
        return false
    modifier := (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C
    other := !injected && modifier && InputState.Role(vk, sc, false) ? OtherPhysicalKeyDown(vk) : false
    pulse := vk = 0x13 || vk = 3 || vk = 0x2C
    event := InputState.Handle(vk, sc, down, injected, A_TickCount, SettingsOpen || RecoveryPaused, false, pulse, other)
    captured := ObserveRecording(vk, sc, down, injected, false, pulse)
    if event.Action
        QueueBoundAction(event.Action, event.Generation)
    return event.Consume || captured
}
RecorderMouseAreaAllowed() {
    global RecordCaptureControl, SettingsWindow
    if !IsObject(RecordCaptureControl) || !IsObject(SettingsWindow)
        return false
    point := Buffer(8)
    if !DllCall("GetCursorPos", "Ptr", point)
        return false
    hwnd := DllCall("WindowFromPoint", "Int64", NumGet(point, 0, "Int64"), "Ptr")
    ; WindowFromPoint may skip a Static control. Use its actual bounds and our own GUI ancestry.
    if hwnd != SettingsWindow.Hwnd && !DllCall("IsChild", "Ptr", SettingsWindow.Hwnd, "Ptr", hwnd)
        return false
    rect := Buffer(16)
    return DllCall("GetWindowRect", "Ptr", RecordCaptureControl.Hwnd, "Ptr", rect)
        && RecorderPointInside(NumGet(point,0,"Int"),NumGet(point,4,"Int"),
            NumGet(rect,0,"Int"),NumGet(rect,4,"Int"),NumGet(rect,8,"Int"),NumGet(rect,12,"Int"))
}
RecorderPointInside(x,y,left,top,right,bottom) => x >= left && y >= top && x < right && y < bottom
RecorderMayCapture(active, down, withinTime, settings, focused, mouse, captureArea) =>
    active && down && withinTime && settings && focused && (!mouse || captureArea)
RecorderExitKey(vk, mouse) => !mouse && vk = 0x1B
ObserveRecording(vk, sc, down, injected, mouse, pulse) {
    global RecordingActive, RecordHeldVK, RecordHeldSC, RecordHeldMouse, RecordHeldNative, RecordedCombination
    global RecordingCancelled, RecordExpiry, SettingsOpen, SettingsWindow, RecordingGeneration
    global RecordingPendingVK, RecordingPendingSC, RecordingPendingMouse, InputState
    if injected
        return false
    ; Escape always reaches the GUI: stop recording first, then cancel settings.
    if RecorderExitKey(vk, mouse)
        return false
    if RecordHeldVK && vk = RecordHeldVK && sc = RecordHeldSC && mouse = RecordHeldMouse {
        consume := !RecordHeldNative
        if !down {
            RecordHeldVK := 0
            if !RecordingCancelled
                DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", RecordedCombination ? 0x8056 : 0x8055, "Ptr", RecordingGeneration, "Ptr", 0)
        }
        return consume
    }
    if down && RecordHeldVK {
        RecordedCombination := true
        return false
    }
    if !RecordingActive || !down
        return false
    if A_TickCount >= RecordExpiry || !SettingsOpen || !IsObject(SettingsWindow)
        || DllCall("GetForegroundWindow", "Ptr") != SettingsWindow.Hwnd {
        RecordingActive := false
        return false
    }
    ; Save/cancel/close and the record buttons always remain native mouse targets.
    if !RecorderMayCapture(RecordingActive, down, A_TickCount < RecordExpiry, SettingsOpen, true, mouse, mouse ? RecorderMouseAreaAllowed() : false)
        return false
    RecordingActive := false, RecordingCancelled := false
    RecordHeldVK := pulse ? 0 : vk, RecordHeldSC := sc, RecordHeldMouse := mouse
    RecordHeldNative := !mouse && ((vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C)
    RecordedCombination := InputState.OtherModifiers(RecordHeldNative ? vk : 0)
    RecordingPendingVK := vk, RecordingPendingSC := sc, RecordingPendingMouse := mouse
    if pulse
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", RecordedCombination ? 0x8056 : 0x8055, "Ptr", RecordingGeneration, "Ptr", 0)
    return !RecordHeldNative
}
BeginKeyRecording(*) {
    global SettingsOpen, RecordingActive, RecordExpiry, RecordedSpec, RecordDisplay, RecordButton
    global RecordHeldVK, RecordingGeneration, RecordingCancelled
    if !SettingsOpen || RecordHeldVK
        return
    CancelKeyRecording()
    RecordingGeneration += 1, RecordingCancelled := false
    RecordedSpec := 0, RecordingActive := true, RecordExpiry := A_TickCount + 10000
    RecordDisplay.Text := (RecordingTarget = "close" ? "正在录制关闭键" : "正在录制打开键") "：按下后松开。鼠标请在大区域内操作；Esc 停止。"
    SetTimer(RecordingTimeout, -10000)
    SetTimer(RecorderWatch, 100)
}
RecordingCompleted(generation := 0, *) {
    global RecordingGeneration, RecordingPendingVK, RecordingPendingSC, RecordingPendingMouse
    global SettingsOpen, RecordedSpec, RecordDisplay, RecordingTarget, ProposedTriggerSpec, ProposedCloseSpec
    if generation != RecordingGeneration || !SettingsOpen
        return
    SetTimer(RecordingTimeout, 0), SetTimer(RecorderWatch, 0)
    try {
        spec := RecordingPendingMouse ? MouseSpecFromVK(RecordingPendingVK) : KeySpecFromCodes(RecordingPendingVK, RecordingPendingSC)
        RecordedSpec := spec
        if RecordingTarget = "close"
            ProposedCloseSpec := spec
        else
            ProposedTriggerSpec := spec
        UpdateSettingLabels()
        RecordDisplay.Text := "已选：" SettingsKeyLabel(spec) "。保存后生效。`n"
            . (spec.Modifier ? "独立按下松开才触发，原组合键保留。" : "启用后占用此键原功能；取消不生效。")
    } catch as problem {
        RecordedSpec := 0, RecordDisplay.Text := problem.Message
    }
}
CancelKeyRecording(*) {
    global RecordingActive, RecordingPendingVK, RecordingPendingSC, RecordingCancelled, RecordingGeneration
    RecordingActive := false, RecordingCancelled := true, RecordingGeneration += 1
    RecordingPendingVK := 0, RecordingPendingSC := 0
    SetTimer(RecordingTimeout, 0), SetTimer(RecorderWatch, 0)
}
RecordingTimeout(*) {
    global SettingsOpen, RecordDisplay
    CancelKeyRecording()
    if SettingsOpen
        RecordDisplay.Text := "录制超时；可以重新录制、恢复默认或取消。"
}
RecorderWatch(*) {
    global RecordingActive, SettingsOpen, SettingsWindow, RecordDisplay
    if RecordingActive && (!SettingsOpen || !IsObject(SettingsWindow) || DllCall("GetForegroundWindow", "Ptr") != SettingsWindow.Hwnd) {
        CancelKeyRecording()
        if SettingsOpen
            RecordDisplay.Text := "设置窗口失去焦点，已停止录制。"
    }
}
RecordingCombinationDetected(generation := 0, *) {
    global SettingsOpen, RecordingGeneration, RecordedSpec, RecordDisplay
    if SettingsOpen && generation = RecordingGeneration {
        RecordedSpec := 0
        RecordDisplay.Text := "检测到组合输入；本版只绑定单键。松开后重新录制，保存/取消保持可用。"
    }
}
StopKeyboardObserver(*) {
    global KeyboardObserverHandle, KeyboardObserverCallback
    CancelKeyRecording()
    if KeyboardObserverHandle
        DllCall("UnhookWindowsHookEx", "Ptr", KeyboardObserverHandle)
    KeyboardObserverHandle := 0
    if KeyboardObserverCallback
        CallbackFree(KeyboardObserverCallback)
    KeyboardObserverCallback := 0
}
