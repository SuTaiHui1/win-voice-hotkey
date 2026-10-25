#Requires AutoHotkey v2.0
#SingleInstance Ignore
#MaxThreadsPerHotkey 1
#Warn All, StdOut
OnError(ReportRuntimeError)
#Include RuntimeState.ahk
#Include AppPaths.ahk
#Include KeyCatalog.ahk
#Include SupportDiagnostics.ahk
#Include InputRouter.ahk
#Include KeyboardObserver.ahk
#Include KeySettings.ahk
#Include GlobalRuntime.ahk
#Include CloseBrokerRuntime.ahk
global SettingsOpen := false, SettingsWindow := 0

ReportRuntimeError(problem, mode) {
    global FixtureTest, HookTest
    diagnostic := (IsSet(FixtureTest) && FixtureTest) || (IsSet(HookTest) && HookTest)
    detail := diagnostic ? problem.Message "`n" problem.Stack : "see local project line " problem.Line
    global RuntimeState
    if IsObject(RuntimeState)
        try RuntimeState.Fail(Type(problem) ": " problem.Message)
    try FileAppend("Gate runtime error " Type(problem) ": " detail "`n", "**")
    ExitApp(1)
}

global ConfigPath := DataDir "\config.ini"
global TriggerKey := IniRead(ConfigPath, "Mapping", "Key", "XButton1")
global FixtureTest := false, HookTest := false, PhysicalTest := false
global LastProbeReason := "global_mapping", LastControlType := 0
global Armed := IniRead(ConfigPath, "Mapping", "Enabled", "1") = "1"
KeyFixtureMode := false
; Normalize a single keyboard key; never accept arbitrary hotkey syntax.
initialSpec := ResolveKeySpec(TriggerKey)
if !KeyAllowedForBinding(initialSpec)
    throw Error(initialSpec.Reason)
TriggerKey := initialSpec.Key
if !Armed
    ExitApp()
LoadCloseBinding()
try StartPanelWindowTracker()
catch
    CloseLastResult := "tracker_unavailable"
InitializeCloseBrokerMode()

KeyHistory(0)
global Snapshot := 0, SnapshotTick := 0, Held := false
global NativeHeld := false
global RestoredDown := false
global StopRequest := DataDir "\stop.request"
if FileExist(StopRequest)
    FileDelete(StopRequest)
OnMessage(0x8055, RecordingCompleted)
OnMessage(0x8056, RecordingCombinationDetected)
OnMessage(0x8060, OnBoundAction)
UpdateMappingTooltip()
SupportLog("loaded", "open=" TriggerKey " close=" CloseKey " config=" ConfigPath)
; Other mapping tools must not own the same key. No other process is stopped.
A_TrayMenu.Delete()
A_TrayMenu.Add("查看状态", (*) => Run('"' A_ScriptDir '\dependencies\AutoHotkey64.exe" "' A_ScriptDir '\ShowStatus.ahk"'))
A_TrayMenu.Add("设置", OpenKeySettings)
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Add("开机自启", ToggleStartup)
UpdateStartupMenu()
A_TrayMenu.Default := "设置"
OnMessage(0x805E, AppExitRequest)
OnMessage(0x805F, AppSettingsRequest)
; Record metadata from this instance's actual menu, without opening any UI.
RuntimeState.Sections["Tray"]["Count"] := DllCall("GetMenuItemCount", "Ptr", A_TrayMenu.Handle)
Loop DllCall("GetMenuItemCount", "Ptr", A_TrayMenu.Handle) {
    menuText := Buffer(256, 0)
    DllCall("GetMenuStringW", "Ptr", A_TrayMenu.Handle, "UInt", A_Index - 1, "Ptr", menuText, "Int", 128, "UInt", 0x400)
    RuntimeState.Sections["Tray"]["Item" A_Index] := StrGet(menuText)
    RuntimeState.Sections["Tray"]["ItemID" A_Index] := DllCall("GetMenuItemID", "Ptr", A_TrayMenu.Handle, "Int", A_Index - 1, "UInt")
}
RuntimeState.Sections["Tray"]["PID"] := DllCall("GetCurrentProcessId", "UInt")
SetTimer(RefreshGate, 75)
BindTriggerKey(TriggerKey, true)
if SmokeTest
    SetTimer(RunSmokeTest, -300)
else
    Hotkey("^!+F12", EmergencyOpenSettings)
WriteMappingStatus(true)
RuntimeState.Event("main_initialized")
SetTimer(CheckRuntimeState, 2000)
for argument in A_Args
    if argument = "--settings"
        SetTimer(OpenKeySettings, -100)
; Ordinary start/repeated launches do not generate Windows notifications.

WriteMappingStatus(running) {
    global RuntimeState, TriggerKey, SmokeTest
    RuntimeState.Update(Map("MainReady",running ? 1 : 0,"Key",TriggerKey,"Mode",SmokeTest ? "smoke_no_voice" : "global_voice_mapping","DictationLanguage","zh-CN","LanguageResult","not_requested","LanguageRestore","manual"), false)
    WriteCloseStatus()
}

MappingExited(reason, code) {
    global RuntimeState
    SetTimer(CheckRuntimeState, 0)
    if IsObject(RuntimeState)
        try RuntimeState.BeginStop(reason, code)
    try StopActionTimers()
    try StopKeyboardObserver()
    try StopMouseObserver()
    try StopCloseWorker()
    try StopPanelWindowTracker()
    try ReleaseRestoredKey()
    if IsObject(RuntimeState)
        try RuntimeState.Stop(reason, code)
    DllCall("RemovePropW", "Ptr", A_ScriptHwnd, "Str", "WinVoiceHotkeyInstance", "Ptr")
    ReleaseApplicationMutex()
    return 0
}

; Production does not persist trigger history or input metadata.
LogGateEvent(event) {
    global RuntimeState
    if IsObject(RuntimeState)
        RuntimeState.Event(event)
}
