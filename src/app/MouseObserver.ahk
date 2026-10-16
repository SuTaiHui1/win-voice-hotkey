; Standard mouse buttons only; no movement, coordinates, wheel or content retained.
global MouseObserverHandle := 0, MouseObserverCallback := 0
global MouseMappedHeld := false, MouseDispatchNotificationSink := 0
global CloseKey := "", CloseBindingSpec := 0, CloseMappedHeld := false, CloseDispatchNotificationSink := 0


StartMouseObserver() {
    global MouseObserverHandle, MouseObserverCallback
    if MouseObserverHandle
        return
    MouseObserverCallback := CallbackCreate(MouseObserverProc, "Fast", 3)
    MouseObserverHandle := DllCall("SetWindowsHookExW", "Int", 14, "Ptr", MouseObserverCallback,
        "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    if !MouseObserverHandle
        throw OSError()
}
StopMouseObserver(*) {
    global MouseObserverHandle, MouseObserverCallback
    if MouseObserverHandle
        DllCall("UnhookWindowsHookEx", "Ptr", MouseObserverHandle)
    MouseObserverHandle := 0
    if MouseObserverCallback
        CallbackFree(MouseObserverCallback)
    MouseObserverCallback := 0
}
DecodeMouseButton(message, pointer) {
    if message = 0x201 || message = 0x202
        vk := 1
    else if message = 0x204 || message = 0x205
        vk := 2
    else if message = 0x207 || message = 0x208
        vk := 4
    else if message = 0x20B || message = 0x20C {
        which := (NumGet(pointer, 8, "UInt") >> 16) & 0xFFFF
        if which != 1 && which != 2
            return 0
        vk := which + 4
    } else
        return 0
    return {VK: vk, Down: message = 0x201 || message = 0x204 || message = 0x207 || message = 0x20B,
        Injected: !!(NumGet(pointer, 12, "UInt") & 3)}
}
MouseObserverProc(code, message, pointer) {
    if code >= 0 {
        try {
            event := DecodeMouseButton(message, pointer)
            if IsObject(event) && ObserveMouseMetadata(event.VK, event.Down, event.Injected)
                return 1
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "Ptr", message, "Ptr", pointer, "Ptr")
}
ObserveMouseMetadata(vk, down, injected) {
    global RecordingActive, RecordHeldVK, RecordHeldSC, RecordHeldNative, RecordedCombination
    global RecordExpiry, SettingsOpen, SettingsWindow, RecordingPendingVK, RecordingPendingSC
    global BindingSpec, MouseMappedHeld, MouseDispatchNotificationSink
    global SelectedPhysicalDown, SelectedOtherKey
    global CloseBindingSpec, CloseMappedHeld, CloseDispatchNotificationSink
    if injected
        return false
    ; Shift+mouse is a combination too; keep its native behavior and cancel tap.
    if down && SelectedPhysicalDown && IsObject(BindingSpec) && BindingSpec.Modifier
        SelectedOtherKey := true
    if vk != 4 && vk != 5 && vk != 6
        return false
    ; Finish the exact captured press after cancel, timeout, focus loss or settings close.
    if RecordHeldVK = vk && RecordHeldSC = 0 {
        if !down
            RecordHeldVK := 0, RecordHeldNative := false
        return true
    }
    if down && RecordHeldVK {
        RecordedCombination := true
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8056, "Ptr", 0, "Ptr", 0)
        return false
    }
    if RecordingActive && down {
        if A_TickCount >= RecordExpiry || !SettingsOpen || !IsObject(SettingsWindow)
            || DllCall("GetForegroundWindow", "Ptr") != SettingsWindow.Hwnd {
            RecordingActive := false
            return false
        }
        RecordingActive := false
        RecordHeldVK := vk, RecordHeldSC := 0, RecordHeldNative := false
        RecordedCombination := ModifiersHeld()
        RecordingPendingVK := vk, RecordingPendingSC := 0
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", RecordedCombination ? 0x8056 : 0x8055, "Ptr", 0, "Ptr", 0)
        return true
    }
    if IsObject(CloseBindingSpec) && CloseBindingSpec.VK = vk {
        if CloseMappedHeld {
            if !down
                CloseMappedHeld := false
            return true
        }
        if SettingsOpen || !down
            return false
        CloseMappedHeld := true
        if !ModifiersHeld() {
            if IsObject(CloseDispatchNotificationSink)
                CloseDispatchNotificationSink.Call(vk)
            else
                DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8058, "Ptr", vk, "Ptr", 0)
        }
        return true
    }
    if !IsObject(BindingSpec) || !BindingSpec.Mouse || BindingSpec.VK != vk
        return false
    if MouseMappedHeld {
        if !down
            MouseMappedHeld := false
        return true
    }
    if SettingsOpen || !down
        return false
    MouseMappedHeld := true
    ; Suppress both native edges: the selected side button must not navigate.
    if !ModifiersHeld() {
        if IsObject(MouseDispatchNotificationSink)
            MouseDispatchNotificationSink.Call(vk)
        else
            DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8057, "Ptr", vk, "Ptr", 0)
    }
    return true
}
MouseTriggerVoice(vk, *) {
    global SettingsOpen, BindingSpec
    if !SettingsOpen && IsObject(BindingSpec) && BindingSpec.Mouse && BindingSpec.VK = vk
        DispatchVoiceRequest()
}
