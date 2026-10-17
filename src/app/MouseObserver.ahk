; Pointer coordinates are used transiently only to protect settings controls during recording.
global MouseObserverHandle := 0, MouseObserverCallback := 0
global CloseKey := "", CloseBindingSpec := 0
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
    pulse := false
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
    } else if message = 0x20A || message = 0x20E {
        delta := NumGet(pointer, 10, "Short")
        if !delta
            return 0
        vk := message = 0x20A ? (delta > 0 ? 256 : 257) : (delta > 0 ? 259 : 258)
        pulse := true
    } else
        return 0
    return {VK: vk, Down: pulse || message = 0x201 || message = 0x204 || message = 0x207 || message = 0x20B,
        Pulse: pulse, Injected: !!(NumGet(pointer, 12, "UInt") & 3)}
}
MouseObserverProc(code, message, pointer) {
    if code >= 0 {
        try {
            event := DecodeMouseButton(message, pointer)
            if IsObject(event) && ObserveMouseMetadata(event.VK, event.Down, event.Injected, event.Pulse)
                return 1
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "Ptr", message, "Ptr", pointer, "Ptr")
}
ObserveMouseMetadata(vk, down, injected, pulse := false) {
    global InputState, SettingsOpen, RecoveryPaused
    if !IsObject(InputState)
        return false
    event := InputState.Handle(vk, 0, down, injected, A_TickCount, SettingsOpen || RecoveryPaused, true, pulse)
    captured := ObserveRecording(vk, 0, down, injected, true, pulse)
    if event.Action
        QueueBoundAction(event.Action, event.Generation)
    return event.Consume || captured
}
MouseSpecFromVK(vk) {
    static names := Map(1,"LButton",2,"RButton",4,"MButton",5,"XButton1",6,"XButton2",256,"WheelUp",257,"WheelDown",258,"WheelLeft",259,"WheelRight")
    if !names.Has(vk)
        throw Error("未知鼠标按键。")
    return MouseKeySpec(names[vk])
}
