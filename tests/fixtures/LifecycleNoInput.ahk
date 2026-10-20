#Requires AutoHotkey v2.0
#SingleInstance Ignore
#Warn All, StdOut
OnError(FixtureError)
#Include RuntimeState.ahk
#Include AppPaths.ahk
global SettingsOpen := false, SettingsWindow := 0
global ConfigPath := DataDir "\config.ini"
global TriggerKey := IniRead(ConfigPath,"Mapping","Key","F24"), CloseKey := IniRead(ConfigPath,"Mapping","CloseKey","F24")
if FileExist(A_ScriptDir "\fail-start.fixture") {
    RuntimeState.Fail("synthetic_initialization_failure")
    ExitApp(7)
}
RuntimeState.Update(Map("Key",TriggerKey,"CloseKey",CloseKey,"MainReady",1,"CloseBrokerReady",1,"CloseBrokerPID",DllCall("GetCurrentProcessId","UInt"),"Mode","fixture_no_input"))
RuntimeState.Event("fixture_ready")
; No health timer here: the launcher regression deliberately leaves a stale PID
; in the fixture file to exercise native instance discovery, without a race.
Persistent()
FixtureError(problem,*) {
    try RuntimeState.Fail(problem.Message)
    ExitApp(9)
}
MappingExited(reason,code) {
    global RuntimeState
    if IsObject(RuntimeState)
        RuntimeState.Stop(reason,code)
    DllCall("RemovePropW","Ptr",A_ScriptHwnd,"Str","WinVoiceHotkeyInstance","Ptr")
    ReleaseApplicationMutex()
    return 0
}
OpenKeySettings(*) {
}
CloseKeySettings(*) {
}
UpdateMappingTooltip(*) {
}
