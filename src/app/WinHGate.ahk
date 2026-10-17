#Requires AutoHotkey v2.0
#SingleInstance Ignore
#MaxThreadsPerHotkey 1
#Warn All, StdOut
OnError(ReportRuntimeError)
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
    FileAppend("Gate runtime error " Type(problem) ": " detail "`n", "**")
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
OnExit(StopPanelWindowTracker)
StartCloseBroker()

KeyHistory(0)
global Snapshot := 0, SnapshotTick := 0, Held := false
global NativeHeld := false
global RestoredDown := false
global StatusToken := Random(1, 2147483647)
DllCall("SetPropW", "Ptr", A_ScriptHwnd, "WStr", "WinVoiceHotkeyInstance", "Ptr", StatusToken)
global StopRequest := DataDir "\stop.request"
if FileExist(StopRequest)
    FileDelete(StopRequest)
OnExit(ReleaseRestoredKey)
OnExit(MappingExited)
OnExit(StopKeyboardObserver)
OnExit(StopMouseObserver)
OnExit(StopCloseWorker)
OnExit(StopActionTimers)
OnMessage(0x8055, RecordingCompleted)
OnMessage(0x8056, RecordingCombinationDetected)
OnMessage(0x8060, OnBoundAction)
UpdateMappingTooltip()
SupportLog("loaded", "open=" TriggerKey " close=" CloseKey " config=" ConfigPath)
WriteMappingStatus(true)
LogGateEvent("mapping_started")
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
IniWrite(DllCall("GetMenuItemCount", "Ptr", A_TrayMenu.Handle), DataDir "\mapping-state.ini", "Tray", "Count")
Loop DllCall("GetMenuItemCount", "Ptr", A_TrayMenu.Handle) {
    menuText := Buffer(256, 0)
    DllCall("GetMenuStringW", "Ptr", A_TrayMenu.Handle, "UInt", A_Index - 1, "Ptr", menuText, "Int", 128, "UInt", 0x400)
    IniWrite(StrGet(menuText), DataDir "\mapping-state.ini", "Tray", "Item" A_Index)
    IniWrite(DllCall("GetMenuItemID", "Ptr", A_TrayMenu.Handle, "Int", A_Index - 1, "UInt"), DataDir "\mapping-state.ini", "Tray", "ItemID" A_Index)
}
IniWrite(DllCall("GetCurrentProcessId", "UInt"), DataDir "\mapping-state.ini", "Tray", "PID")
SetTimer(RefreshGate, 75)
BindTriggerKey(TriggerKey, true)
if SmokeTest
    SetTimer(RunSmokeTest, -300)
else
    Hotkey("^!+F12", EmergencyOpenSettings)
for argument in A_Args
    if argument = "--settings"
        SetTimer(OpenKeySettings, -100)
; Ordinary start/repeated launches do not generate Windows notifications.

WriteMappingStatus(running) {
    global DataDir
    global PhysicalTest, HookTest, TriggerKey, StatusToken
    stateFile := DataDir "\mapping-state.ini"
    IniWrite(running ? 1 : 0, stateFile, "State", "Running")
    IniWrite(DllCall("GetCurrentProcessId", "UInt"), stateFile, "State", "PID")
    IniWrite(TriggerKey, stateFile, "State", "Key")
    IniWrite("0.1.2", stateFile, "State", "Version")
    IniWrite("release-0.1.2", stateFile, "State", "CandidateBuild")
    IniWrite(A_ScriptHwnd, stateFile, "State", "HWND")
    IniWrite(StatusToken, stateFile, "State", "InstanceToken")
    IniWrite(PhysicalTest ? "physical_diagnostic_no_voice" : HookTest ? "synthetic_diagnostic_no_voice" : "global_voice_mapping", stateFile, "State", "Mode")
    IniWrite(A_NowUTC, stateFile, "State", "UpdatedUTC")
    WriteCloseStatus()
}

MappingExited(*) {
    global DataDir
    LogGateEvent("mapping_stopped")
    DllCall("RemovePropW", "Ptr", A_ScriptHwnd, "WStr", "WinVoiceHotkeyInstance", "Ptr")
    WriteMappingStatus(false)
}

; Production does not persist trigger history or input metadata.
LogGateEvent(event) {
}
