#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError((problem, *) => (FileAppend(problem.Message "`n" problem.Stack, "**"), ExitApp(1)))
#Include KeyCatalog.ahk
#Include KeyboardObserver.ahk
#Include GlobalModifierTap.ahk
#Include GlobalRuntime.ahk
#Include KeySettings.ahk
#Include CloseBrokerRuntime.ahk
global SettingsOpen := false, SettingsWindow := 0, Held := false, NativeHeld := false
global RestoredDown := false, Snapshot := 0, SnapshotTick := 0, TriggerKey := "XButton1"
global ConfigPath := A_ScriptDir "\close-binding-test.ini", Passed := 0, Opens := 0, Closes := 0
global StopRequest := A_ScriptDir "\test-unused-stop.request"
VoiceDispatchSink := CountOpen, CloseActionSink := CountClose
MouseDispatchNotificationSink := MouseTriggerVoice, CloseDispatchNotificationSink := MouseCloseVoice
CountOpen() {
    global Opens
    Opens += 1
}
CountClose() {
    global Closes
    Closes += 1
}
LogGateEvent(*) {
}
WriteMappingStatus(*) {
}
FakeBind(key, enabled) {
}
FailPersist(*) {
    throw Error("expected pair failure")
}
WriteConfig(key, close := "__missing__") {
    global ConfigPath
    f := FileOpen(ConfigPath, "w", "UTF-16")
    f.Write("[Mapping]`nEnabled=1`nKey=" key "`n" (close = "__missing__" ? "" : "CloseKey=" close "`n")), f.Close()
}
Check(ok, label) {
    global Passed
    if !ok
        throw Error(label)
    Passed += 1
}
WriteConfig("XButton1")
LoadCloseBinding()
Check(TriggerKey = "XButton1" && CloseKey = "XButton2", "default preserves successful open button")
Check(IniRead(ConfigPath,"Mapping","CloseKey") = "XButton2", "default persisted")
BindingSpec := ResolveKeySpec(TriggerKey)
for which in [5,6] {
    for repetition in [1,2,3] {
        Check(ObserveMouseMetadata(which,true,false), "both action downs consumed")
        Loop 15
            Check(ObserveMouseMetadata(which,true,false), "held action no repeat")
        Check(ObserveMouseMetadata(which,false,false), "both action ups consumed")
    }
}
Check(Opens = 3 && Closes = 3, "open and close distinct exactly once")
SettingsOpen := true
for which in [5,6] {
    Check(!ObserveMouseMetadata(which,true,false), "settings native down")
    Check(!ObserveMouseMetadata(which,false,false), "settings native up")
}
MouseCloseVoice(6)
Check(Closes = 3, "queued close canceled by settings")
SettingsOpen := false
Check(!ObserveMouseMetadata(6,true,true) && !CloseMappedHeld, "injected close ignored")
ObserveMouseMetadata(6,true,false)
Check(!ObserveMouseMetadata(6,false,true) && CloseMappedHeld, "injected up cannot release physical close")
SettingsOpen := true
Check(ObserveMouseMetadata(6,false,false) && !CloseMappedHeld, "held close release paired across pause")
SettingsOpen := false
for pair in [["XButton1","XButton1"],["XButton1","RShift"],["XButton1","^XButton2"],["XButton1","LButton"]] {
    rejected := false
    try ValidateBindingPair(pair[1],pair[2])
    catch
        rejected := true
    Check(rejected, "conflict and unsupported close rejected")
}
SaveBindingPair("XButton1","MButton",0,FakeBind)
Check(TriggerKey = "XButton1" && CloseKey = "MButton" && CloseBindingSpec.VK = 4, "close-only change preserves opener")
LoadCloseBinding()
Check(CloseKey = "MButton" && IniRead(ConfigPath,"Mapping","Key") = "XButton1", "close restart round trip")
try SaveBindingPair("RShift","XButton2",FailPersist,FakeBind)
Check(TriggerKey = "XButton1" && CloseKey = "MButton", "pair rollback restores live bindings")
Check(IniRead(ConfigPath,"Mapping","Key")="XButton1" && IniRead(ConfigPath,"Mapping","CloseKey")="MButton", "pair rollback restores config")
CloseMappedHeld := true
blocked := false
try SaveBindingPair("XButton1","XButton2",0,FakeBind)
catch
    blocked := true
Check(blocked && CloseKey = "MButton", "cannot rebind while close held")
CloseMappedHeld := false
SaveBindingPair("XButton1","",0,FakeBind)
Check(CloseKey = "" && !IsObject(CloseBindingSpec), "explicit empty close persists disabled")
LoadCloseBinding()
Check(CloseKey = "", "empty close not overwritten by default")
TriggerKey := "XButton2"
WriteConfig(TriggerKey)
LoadCloseBinding()
Check(TriggerKey = "XButton2" && CloseKey = "", "default conflict preserves actual opener")
TriggerKey := "XButton1"
WriteConfig(TriggerKey,"XButton1")
LoadCloseBinding()
Check(TriggerKey = "XButton1" && CloseKey = "", "saved conflict fails safe")
WriteConfig(TriggerKey,"XButton2")
LoadCloseBinding()
OpenKeySettings()
hasOpen := false, hasClose := false
for control in SettingsWindow {
    if control.Text = "录制唤起键"
        hasOpen := true
    if control.Text = "录制关闭键"
        hasClose := true
}
Check(hasOpen && hasClose, "GUI offers separate recorders")
BeginCloseKeyRecording()
Check(RecordingTarget="close" && RecordingActive, "close recorder explicitly armed")
CancelKeyRecording()
RecordingPendingVK := 6, RecordingPendingSC := 0
RecordingCompleted()
Check(RecordedSpec.Mouse && RecordedSpec.Key="XButton2", "close mouse recording resolves")
RememberRecordedCandidate()
Check(ProposedCloseSpec.Key="XButton2" && ProposedTriggerSpec.Key="XButton1", "close candidate leaves opener unchanged")
RecordingPendingVK := 0xA1, RecordingPendingSC := 0x36
RecordingCompleted()
Check(!RecordedSpec.Allowed, "close recorder rejects keyboard candidate clearly")
CloseKeySettings()
Check(!SettingsOpen && !RecordingActive, "recording cleanup")
FileDelete(ConfigPath)
f:=FileOpen(A_ScriptDir "\close-bindings-unit-results.json","w","UTF-8")
f.Write('{"passed":' Passed ',"open_counter":' Opens ',"close_counter":' Closes ',"real_voice_sent":false,"real_panel_closed":false,"user_config_modified":false}'),f.Close()
ExitApp()
