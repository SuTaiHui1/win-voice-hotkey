#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError((problem, *) => (FileAppend(problem.Message "`n" problem.Stack, "**"), ExitApp(1)))
#Include KeyCatalog.ahk
#Include KeyboardObserver.ahk
#Include GlobalModifierTap.ahk
#Include GlobalRuntime.ahk
#Include KeySettings.ahk
global SettingsOpen := false, SettingsWindow := 0, Held := false, NativeHeld := false
global RestoredDown := false, Snapshot := 0, SnapshotTick := 0, TriggerKey := "RShift"
global StopRequest := A_ScriptDir "\test-unused-stop.request"
global Count := 0, Passed := 0, Bound := [], ConfigPath := A_ScriptDir "\mouse-test-config.ini"
VoiceDispatchSink := CountDispatch
MouseDispatchNotificationSink := MouseTriggerVoice
CountDispatch() {
    global Count
    Count += 1
}
LogGateEvent(*) {
}
WriteMappingStatus(*) {
}
Check(ok, label) {
    global Passed
    if !ok
        throw Error(label)
    Passed += 1
}
FakeBind(key, enabled) {
    global Bound
    Bound.Push(key ":" enabled)
}
FailPersist(*) {
    throw Error("expected persistence failure")
}
for mouseName in ["MButton", "XButton1", "XButton2"] {
    spec := ResolveKeySpec(mouseName)
    Check(spec.Mouse && spec.Allowed && !spec.Modifier && spec.SC = 0, "mouse catalog")
    Check(ResolveKeySpec(StrLower(mouseName)).Key = mouseName, "case normalization")
    BindingSpec := spec
    previous := Count
    Check(ObserveMouseMetadata(spec.VK, true, false), "native down suppressed")
    Check(!ObserveMouseMetadata(spec.VK, false, true) && MouseMappedHeld, "injected release cannot clear physical latch")
    Loop 15
        Check(ObserveMouseMetadata(spec.VK, true, false), "held down stays suppressed")
    Check(Count = previous + 1 && MouseMappedHeld, "held single dispatch")
    Check(ObserveMouseMetadata(spec.VK, false, false) && !MouseMappedHeld, "native up suppressed and released")
    Check(!ObserveMouseMetadata(spec.VK, false, false), "orphan up passed")
    Check(!ObserveMouseMetadata(spec.VK, true, true) && Count = previous + 1, "injected ignored")
    Loop 12 {
        ObserveMouseMetadata(spec.VK, true, false)
        ObserveMouseMetadata(spec.VK, false, false)
    }
    Check(Count = previous + 13, "rapid clicks exactly once each")
    SettingsOpen := true
    previousPaused := Count
    MouseTriggerVoice(spec.VK)
    Check(Count = previousPaused, "queued dispatch canceled while settings open")
    Check(!ObserveMouseMetadata(spec.VK, true, false), "settings native down preserved")
    Check(!ObserveMouseMetadata(spec.VK, false, false), "settings native up preserved")
    Check(Count = previous + 13, "settings no dispatch")
    SettingsOpen := false
    otherVK := spec.VK = 4 ? 5 : 4
    Check(!ObserveMouseMetadata(otherVK, true, false), "unselected mouse button native preserved")
    ObserveMouseMetadata(spec.VK, true, false)
    SettingsOpen := true
    Check(ObserveMouseMetadata(spec.VK, false, false) && !MouseMappedHeld, "release after settings opens")
    SettingsOpen := false
    ; Explicitly armed recorder, only current window identity is queried.
    SettingsWindow := {Hwnd: DllCall("GetForegroundWindow", "Ptr")}
    SettingsOpen := true, RecordingActive := true, RecordExpiry := A_TickCount + 10000
    Check(!ObserveMouseMetadata(1, true, false) && RecordingActive, "left save click not recorded")
    Check(!ObserveMouseMetadata(2, true, false) && RecordingActive, "right menu click not recorded")
    Check(ObserveMouseMetadata(spec.VK, true, false) && RecordHeldVK = spec.VK && !RecordingActive, "mouse captured")
    RecordedSpec := 0, RecordDisplay := {Text: ""}
    RecordingCompleted()
    Check(IsObject(RecordedSpec) && RecordedSpec.Key = mouseName, "recorder resolves mouse")
    CancelKeyRecording()
    SettingsOpen := false
    Check(ObserveMouseMetadata(spec.VK, false, false) && !RecordHeldVK, "cancel still consumes captured up")
    SettingsOpen := true, RecordingActive := true, RecordExpiry := A_TickCount - 1
    Check(!ObserveMouseMetadata(spec.VK, true, false) && !RecordingActive, "timeout restores native")
    RecordingActive := true, RecordExpiry := A_TickCount + 10000
    SettingsWindow := {Hwnd: -1}
    Check(!ObserveMouseMetadata(spec.VK, true, false) && !RecordingActive, "focus loss cancels")
    SettingsOpen := false
    ; INI round trip and transactional rebind use this test's own config.
    config := FileOpen(ConfigPath, "w", "UTF-8")
    config.Write("[Mapping]`nEnabled=1`nKey=" TriggerKey "`n"), config.Close()
    SwitchTriggerKey(mouseName, 0, FakeBind)
    Check(TriggerKey = mouseName && IniRead(ConfigPath,"Mapping","Key") = mouseName, "save persistence")
    Check(ResolveKeySpec(IniRead(ConfigPath,"Mapping","Key")).Mouse, "restart catalog compatibility")
    beforeRollback := TriggerKey
    try SwitchTriggerKey("RShift", FailPersist, FakeBind)
    Check(TriggerKey = beforeRollback && IniRead(ConfigPath,"Mapping","Key") = beforeRollback, "failed save rolls back")
}
for invalid in ["LButton", "RButton", "WheelUp", "XButton3", "^XButton1", "XButton1 & A"]
    Check(!SupportedTriggerKey(invalid), "unsupported and combinations rejected")
BindingSpec := ResolveKeySpec("RShift")
for mouseVK in [1,2,4,5,6] {
    SelectedPhysicalDown := true, SelectedOtherKey := false
    Check(!ObserveMouseMetadata(mouseVK,true,false) && SelectedOtherKey, "Shift mouse combination preserved")
    SelectedPhysicalDown := false
}
for data in [[0x207,0,4,true],[0x208,0,4,false],[0x20B,0x10000,5,true],[0x20C,0x10000,5,false],[0x20B,0x20000,6,true],[0x20C,0x20000,6,false]] {
    mouseBuf := Buffer(32,0)
    NumPut("UInt",data[2],mouseBuf,8)
    event := DecodeMouseButton(data[1],mouseBuf)
    Check(event.VK = data[3] && event.Down = data[4] && !event.Injected, "native ABI mouse decode")
    NumPut("UInt",1,mouseBuf,12)
    Check(DecodeMouseButton(data[1],mouseBuf).Injected, "injection flag decode")
}
Check(!IsObject(DecodeMouseButton(0x200,Buffer(32,0))), "movement ignored")
Check(!ObserveMouseMetadata(4,true,true), "injected never binds")
; Install/uninstall the actual low-level hook on isolated test desktop, no input injection.
StartMouseObserver()
Check(MouseObserverHandle != 0, "native mouse hook installs")
for bindName in ["MButton", "XButton1", "XButton2"] {
    BindTriggerKey(bindName, true)
    Check(BindingSpec.Key = bindName && KeyboardObserverHandle && MouseObserverHandle, "real binder accepts mouse")
    BindTriggerKey(bindName, false)
}
BindTriggerKey("RShift", true)
Check(BindingSpec.Key = "RShift" && !BindingSpec.Mouse, "real binder returns to keyboard")
BindTriggerKey("RShift", false)
StopKeyboardObserver()
StopMouseObserver()
Check(MouseObserverHandle = 0 && MouseObserverCallback = 0, "hook cleanup")
TriggerKey := "RShift"
OpenKeySettings()
Check(SettingsOpen && IsObject(SettingsWindow), "settings GUI opens")
mouseHelp := false, keyboardOnly := false
for control in SettingsWindow {
    if InStr(control.Text,"XButton1")
        mouseHelp := true
    if InStr(control.Text,"不支持鼠标")
        keyboardOnly := true
}
Check(mouseHelp && !keyboardOnly, "GUI explains mouse support")
BeginKeyRecording()
Check(RecordingActive && !IsObject(RecordedSpec), "explicit recording arm")
CancelKeyRecording()
Check(!RecordingActive && !RecordingPendingVK, "cancel clears candidate")
CloseKeySettings()
Check(!SettingsOpen, "settings GUI exits cleanly")
FileDelete(ConfigPath)
result := FileOpen(A_ScriptDir "\mouse-mapping-unit-results.json", "w", "UTF-8")
result.Write('{"passed":' Passed ',"dispatch_counter":' Count ',"real_WinH_sent":false,"microphone_used":false,"user_config_modified":false,"native_hook_install_uninstall":"isolated_test_desktop"}')
result.Close()
ExitApp()
