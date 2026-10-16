; Global key mapping: no UIA, MSAA, IA2, focus or editable-control probes.
global VoiceDispatchSink := 0
GlobalPressAllowed(injected, down, settings, modifiers, nativeHeld, held) =>
    !injected && down && !settings && (held || (!nativeHeld && !modifiers))

GateReady(*) {
    global SelectedEventInjected, SelectedPhysicalDown, SettingsOpen, NativeHeld, Held
    return GlobalPressAllowed(SelectedEventInjected, SelectedPhysicalDown, SettingsOpen, ModifiersHeld(), NativeHeld, Held)
}
ModifiersHeld() => GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
    || GetKeyState("Shift", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
TriggerIsDown() {
    global SelectedPhysicalDown
    return SelectedPhysicalDown
}
WaitTriggerRelease() {
    while TriggerIsDown()
        Sleep(10)
}
TriggerVoice(*) {
    global Held, SettingsOpen, SelectedEventInjected, SelectedPhysicalDown
    if Held
        return
    Held := true
    try {
        if !SettingsOpen && !SelectedEventInjected && SelectedPhysicalDown && !ModifiersHeld()
            DispatchVoiceRequest()
        WaitTriggerRelease()
    } finally Held := false
}
DispatchVoiceRequest() {
    global VoiceDispatchSink
    if IsObject(VoiceDispatchSink) {
        VoiceDispatchSink.Call()
        return
    }
    LogGateEvent("voice_shortcut_requested")
    Send("#h")
}
ObserveNativePress(*) {
    global NativeHeld, SelectedEventInjected
    if SelectedEventInjected
        return
    NativeHeld := true
    try WaitTriggerRelease()
    finally NativeHeld := false
}
; Retained binder compatibility; global mapping never synthesizes selected keys.
RecoveryActive(*) => false
RecoveredNativeRelease(*) {
}
ReleaseRestoredKey(*) {
}
RefreshGate() {
    global StopRequest, NativeHeld, ModifierPending, SettingsOpen, PendingTapCount
    if FileExist(StopRequest) {
        FileDelete(StopRequest)
        ExitApp()
    }
    if SettingsOpen {
        ModifierPending := 0
        PendingTapCount := 0
    }
    if NativeHeld && !TriggerIsDown()
        NativeHeld := false
}
