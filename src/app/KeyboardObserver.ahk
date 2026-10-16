#Include MouseObserver.ahk
; Native hook observes only the configured key; during an explicitly armed
; recorder it retains one VK/SC, and during a modifier tap only a combo boolean.
; No strings, characters, key history, or unrelated key identities are stored.
global KeyboardObserverHandle := 0, KeyboardObserverCallback := 0
global BindingSpec := 0, SelectedPhysicalDown := false, SelectedEventInjected := true
global SelectedOtherKey := false, ModifierPending := 0
global RecordingActive := false, RecordHeldVK := 0, RecordHeldSC := 0
global RecordHeldNative := false, RecordedCombination := false
global RecordedSpec := 0, RecordExpiry := 0, RecordDisplay := 0, RecordButton := 0
global RecordingPendingVK := 0, RecordingPendingSC := 0
global RecordingTarget := "open"

StartKeyboardObserver(spec) {
    global BindingSpec, SelectedPhysicalDown, SelectedEventInjected
    global KeyboardObserverHandle, KeyboardObserverCallback
    if KeyboardObserverHandle
        DllCall("UnhookWindowsHookEx", "Ptr", KeyboardObserverHandle)
    KeyboardObserverHandle := 0
    if !KeyboardObserverCallback
        KeyboardObserverCallback := CallbackCreate(KeyboardObserverProc, "Fast", 3)
    BindingSpec := spec
    StartMouseObserver()
    SelectedPhysicalDown := false, SelectedEventInjected := true
    KeyboardObserverHandle := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", KeyboardObserverCallback,
        "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    if !KeyboardObserverHandle
        throw OSError()
}

KeyboardObserverProc(code, message, pointer) {
    global SelectedPhysicalDown, SelectedEventInjected, SelectedOtherKey, RecordingActive
    if code >= 0 {
        try {
            event := DecodeKeyboardEvent(message, pointer)
            if ObserveKeyboardMetadata(event.VK, event.SC, event.Down, event.Injected)
                return 1
        } catch {
            ; Never suppress an unknown event on a hook error.
            SelectedPhysicalDown := false, SelectedEventInjected := true
            SelectedOtherKey := true, RecordingActive := false
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "Ptr", message, "Ptr", pointer, "Ptr")
}

DecodeKeyboardEvent(message, pointer) {
    flags := NumGet(pointer, 8, "UInt")
    vk := NumGet(pointer, 0, "UInt"), rawSC := NumGet(pointer, 4, "UInt")
    if vk = 0x10 {
        if (rawSC & 0xFF) = 0x2A
            vk := 0xA0
        else if (rawSC & 0xFF) = 0x36
            vk := 0xA1
    }
    return {VK: vk, SC: rawSC | (flags & 1 ? 0x100 : 0),
        Down: message = 0x100 || message = 0x104, Injected: !!(flags & 0x12)}
}

ObserveKeyboardMetadata(vk, sc, down, injected) {
    global BindingSpec, SelectedPhysicalDown, SelectedEventInjected, SelectedOtherKey
    global RecordingActive, RecordHeldVK, RecordHeldSC, RecordHeldNative, RecordedCombination, RecordExpiry, SettingsOpen, SettingsWindow
    global RecordingPendingVK, RecordingPendingSC
    ; Finish the exact recorded press, including repeats/up, even after cancel.
    if !injected && RecordHeldVK && vk = RecordHeldVK && sc = RecordHeldSC {
        suppressed := !RecordHeldNative
        if !down
            RecordHeldVK := 0, RecordHeldSC := 0, RecordHeldNative := false
        return suppressed
    }
    if !injected && down && RecordHeldVK {
        RecordedCombination := true
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8056, "Ptr", 0, "Ptr", 0)
    }
    if RecordingActive && !injected && down {
        if A_TickCount >= RecordExpiry || !SettingsOpen || !IsObject(SettingsWindow)
            || DllCall("GetForegroundWindow", "Ptr") != SettingsWindow.Hwnd {
            RecordingActive := false
            return false
        }
        if vk >= 8 && vk <= 254 {
            RecordingActive := false
            RecordHeldVK := vk, RecordHeldSC := sc
            ; Never suppress a modifier while recording: retain all native
            ; modifier combinations, including Windows security shortcuts.
            RecordHeldNative := vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C || (vk >= 0xA0 && vk <= 0xA5)
            RecordedCombination := false
            RecordingPendingVK := vk, RecordingPendingSC := sc
            ; Resolve names/update controls outside the low-level callback.
            DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8055, "Ptr", 0, "Ptr", 0)
            return !RecordHeldNative
        }
    }
    if !IsObject(BindingSpec)
        return false
    matched := !BindingSpec.Mouse && (BindingSpec.Modifier ? vk = BindingSpec.VK : BindingSpec.SC ? sc = BindingSpec.SC : vk = BindingSpec.VK)
    if matched {
        SelectedEventInjected := injected
        if !injected {
            if down && !SelectedPhysicalDown
                SelectedOtherKey := false
            SelectedPhysicalDown := down
        }
    } else if down && SelectedPhysicalDown && BindingSpec.Modifier
        SelectedOtherKey := true
    return false
}

BeginKeyRecording(*) {
    global SettingsOpen, SettingsWindow, RecordingActive, RecordExpiry, RecordedSpec, RecordDisplay, RecordButton
    global RecordHeldVK
    if !SettingsOpen || RecordHeldVK
        return
    CancelKeyRecording()
    RecordedSpec := 0
    RecordDisplay.Text := "请在 10 秒内按一个键盘键、鼠标中键或侧键，然后松开。左/右鼠标键不录制。"
    RecordButton.Text := "重新录制按键"
    RecordingActive := true
    RecordExpiry := A_TickCount + 10000
    SetTimer(RecordingTimeout, -10000)
    SetTimer(RecorderWatch, 100)
}

RecordingCompleted(*) {
    global RecordingPendingVK, RecordingPendingSC, SettingsOpen, RecordedSpec, RecordDisplay
    global RecordingTarget
    SetTimer(RecordingTimeout, 0)
    SetTimer(RecorderWatch, 0)
    vk := RecordingPendingVK, sc := RecordingPendingSC
    RecordingPendingVK := 0, RecordingPendingSC := 0
    if !SettingsOpen || !vk
        return
    try {
        spec := vk >= 4 && vk <= 6 && sc = 0 ? MouseKeySpec(vk = 4 ? "MButton" : vk = 5 ? "XButton1" : "XButton2") : KeySpecFromCodes(vk, sc)
        if RecordingTarget = "close" && !spec.Mouse
            spec.Allowed := false, spec.Reason := "关闭键仅支持鼠标中键、XButton1 或 XButton2；请重新录制。"
        RecordedSpec := spec
        RecordDisplay.Text := spec.Label "`n" (spec.Allowed ? KeyOccupancyWarning(spec) : spec.Reason)
    } catch as problem {
        RecordedSpec := 0
        RecordDisplay.Text := problem.Message
    }
}

CancelKeyRecording(*) {
    global RecordingActive, RecordingPendingVK, RecordingPendingSC
    RecordingActive := false
    RecordingPendingVK := 0, RecordingPendingSC := 0
    SetTimer(RecordingTimeout, 0)
    SetTimer(RecorderWatch, 0)
}

RecordingTimeout(*) {
    global RecordingActive, SettingsOpen, RecordDisplay
    RecordingActive := false
    SetTimer(RecorderWatch, 0)
    if SettingsOpen
        RecordDisplay.Text := "录制已超时。请重新录制清单内的一个物理单键，或取消。"
}

RecorderWatch(*) {
    global RecordingActive, SettingsOpen, SettingsWindow, RecordDisplay
    if RecordingActive && (!SettingsOpen || !IsObject(SettingsWindow)
        || DllCall("GetForegroundWindow", "Ptr") != SettingsWindow.Hwnd) {
        CancelKeyRecording()
        if SettingsOpen
            RecordDisplay.Text := "设置窗口失去焦点，录制已停止。"
    }
}

RecordingCombinationDetected(*) {
    global SettingsOpen, RecordedCombination, RecordedSpec, RecordDisplay
    if SettingsOpen && RecordedCombination {
        RecordedSpec := 0
        RecordDisplay.Text := "检测到组合键。加号/括号等由 Shift 与其他键组成；请选择对应数字/符号键，或只录制 Shift 单键。请松开后重新录制。"
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
