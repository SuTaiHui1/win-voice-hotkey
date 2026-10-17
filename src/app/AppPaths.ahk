; Runtime state is never written into the source or installation folder.
global DataDir := EnvGet("WIN_VOICE_HOTKEY_DATA_DIR")
if DataDir = ""
    DataDir := A_AppData "\WinVoiceHotkey"
DirCreate(DataDir)
global SmokeTest := false
for argument in A_Args
    if argument = "--smoke-test"
        SmokeTest := true
global ApplicationMutex := 0
if !SmokeTest {
    ApplicationMutex := DllCall("CreateMutexW", "Ptr", 0, "Int", false, "WStr", "Local\WinVoiceHotkey.App", "Ptr")
    if !ApplicationMutex || A_LastError = 183
        ExitApp()
    OnExit(ReleaseApplicationMutex)
}
global StartupLink := (SmokeTest ? DataDir "\startup-test" : A_Startup) "\WinVoiceHotkey.lnk"
global LauncherPath := A_ScriptDir "\..\WinVoiceHotkey.exe"

ToggleStartup(*) {
    global StartupLink, LauncherPath
    if FileExist(StartupLink)
        FileDelete(StartupLink)
    else {
        SplitPath(StartupLink, , &folder)
        DirCreate(folder)
        FileCreateShortcut(LauncherPath, StartupLink, A_ScriptDir "\..", , "Windows 语音输入快捷键工具")
    }
    UpdateStartupMenu()
}
UpdateStartupMenu() {
    global StartupLink
    if FileExist(StartupLink)
        A_TrayMenu.Check("开机自启")
    else
        A_TrayMenu.Uncheck("开机自启")
}
AppExitRequest(*) {
    ExitApp()
}
AppSettingsRequest(*) {
    OpenKeySettings()
}
RunSmokeTest(*) {
    global DataDir, TriggerKey, CloseKey, ConfigPath, StartupLink, SettingsOpen, SettingsWindow, CloseBrokerReady
    try {
        deadline := A_TickCount + 4000
        while !CloseBrokerReady && A_TickCount < deadline
            Sleep(25)
        if !CloseBrokerReady
            throw Error("close broker did not become ready")
        OpenKeySettings()
        if !SettingsOpen || !IsObject(SettingsWindow)
            throw Error("settings did not open")
        CloseKeySettings()
        ToggleStartup()
        if !FileExist(StartupLink)
            throw Error("isolated startup shortcut not created")
        ToggleStartup()
        if FileExist(StartupLink)
            throw Error("isolated startup shortcut not removed")
        if IniRead(ConfigPath, "Mapping", "Key") != TriggerKey || IniRead(ConfigPath, "Mapping", "CloseKey") != CloseKey
            throw Error("configuration changed")
        FileAppend('{"settings_opened":true,"settings_closed":true,"startup_roundtrip":true,"broker_ready":true,"hooks_installed":false,"microphone_used":false}', DataDir "\smoke-results.json", "UTF-8-RAW")
        ExitApp()
    } catch as problem {
        FileAppend(problem.Message, DataDir "\smoke-error.txt", "UTF-8-RAW")
        ExitApp(1)
    }
}

ReleaseApplicationMutex(*) {
    global ApplicationMutex
    if ApplicationMutex {
        handle := ApplicationMutex
        ApplicationMutex := 0
        DllCall("CloseHandle", "Ptr", handle)
    }
    return 0
}
