#Include CloseBindings.ahk
BindTriggerKey(key, enabled) {
    spec := ResolveKeySpec(key)
    if !KeyAllowedForBinding(spec)
        throw Error(spec.Reason)
    key := spec.Key
    option := enabled ? "On T1" : "Off"
    if spec.Mouse {
        if enabled
            StartKeyboardObserver(spec)
        return
    }
    if spec.Modifier {
        HotIf()
        Hotkey("~$*" key, ModifierPressed, option)
        Hotkey("~$*" key " up", ModifierReleased, option)
        if enabled
            StartKeyboardObserver(spec)
        return
    }
    HotIf(GateReady)
    try Hotkey("$*" key, TriggerVoice, option)
    finally HotIf()
    Hotkey("~$*" key, ObserveNativePress, option)
    HotIf(RecoveryActive)
    try Hotkey("~$*" key " up", RecoveredNativeRelease, option)
    finally HotIf()
    if enabled
        StartKeyboardObserver(spec)
}

PersistTriggerKey(key) {
    global ConfigPath
    IniWrite(key, ConfigPath, "Mapping", "Key")
}

SwitchTriggerKey(newKey, persist := 0, bind := 0) {
    global TriggerKey, Held, NativeHeld, RestoredDown, Snapshot, SnapshotTick, ConfigPath
    global RecordHeldVK, ModifierPending, SelectedPhysicalDown, MouseMappedHeld
    spec := ResolveKeySpec(newKey)
    if !KeyAllowedForBinding(spec)
        throw Error(spec.Reason)
    newKey := spec.Key
    if Held || NativeHeld || RestoredDown || RecordHeldVK || MouseMappedHeld || SelectedPhysicalDown || IsObject(ModifierPending)
        || GetKeyState(TriggerKey, "P") || GetKeyState(newKey, "P")
        throw Error("请先松开触发键，等待本次按键结束，再保存。")
    if newKey = TriggerKey
        return
    oldKey := TriggerKey
    originalConfig := FileRead(ConfigPath, "RAW")
    binder := bind ? bind : BindTriggerKey
    Critical("On")
    try {
        binder(oldKey, false)
        binder(newKey, true)
        (persist ? persist : PersistTriggerKey)(newKey)
        TriggerKey := newKey
        Snapshot := 0, SnapshotTick := 0
    } catch as problem {
        ; A partially registered new key must never remain active.
        try binder(newKey, false)
        try {
            configStream := FileOpen(ConfigPath, "w")
            configStream.RawWrite(originalConfig)
            configStream.Close()
        } catch {
            ExitApp(1)
        }
        try binder(oldKey, true)
        catch {
            ; Fail closed if rollback cannot restore the known binding.
            ExitApp(1)
        }
        TriggerKey := oldKey
        throw problem
    } finally Critical("Off")
}

OpenKeySettings(*) {
    global SettingsOpen, SettingsWindow, Held, NativeHeld, RestoredDown, TriggerKey
    global RecordedSpec, RecordDisplay, RecordButton
    global CloseKey, ProposedTriggerSpec, ProposedCloseSpec, RecordingTarget, OpenRecordButton, CloseRecordButton, CloseMappedHeld
    if SettingsOpen {
        SettingsWindow.Show()
        return
    }
    if Held || NativeHeld || RestoredDown || CloseMappedHeld || GetKeyState(TriggerKey, "P") {
        MsgBox("请先松开触发键，再打开设置。", "语音输入设置")
        return
    }
    SettingsOpen := true
    window := Gui(, "语音输入设置")
    SettingsWindow := window
    RecordedSpec := ResolveKeySpec(TriggerKey)
    ProposedTriggerSpec := RecordedSpec
    ProposedCloseSpec := CloseKey = "" ? 0 : ResolveKeySpec(CloseKey)
    RecordingTarget := "open"
    window.AddText("w510", "当前触发键：" RecordedSpec.Label)
    window.AddText("w510", "点击录制后，按一个键再松开，10 秒超时。支持键盘单键、鼠标中键和两个标准侧键；不支持组合键。")
    RecordButton := window.AddButton("w150", "录制按键")
    OpenRecordButton := RecordButton
    RecordButton.Text := "录制唤起键"
    RecordButton.OnEvent("Click", BeginOpenKeyRecording)
    window.AddText("xm w510", "当前关闭键：" (IsObject(ProposedCloseSpec) ? ProposedCloseSpec.Label : "未设置"))
    CloseRecordButton := window.AddButton("w150", "录制关闭键")
    CloseRecordButton.OnEvent("Click", BeginCloseKeyRecording)
    window.AddText("xm w510", "关闭键支持中键和两个侧键，须与唤起键不同。关闭键全局占用，不执行前进/后退；无语音面板时安全无操作。设置中恢复原功能。")
    stopRecord := window.AddButton("x+10 w110", "停止录制")
    stopRecord.OnEvent("Click", StopRecordingButton)
    RecordDisplay := window.AddText("xm w510 h90", RecordedSpec.Label "`n" KeyOccupancyWarning(RecordedSpec))
    window.AddText("w510", "可选：原键盘单键及鼠标中键、XButton1（后退）、XButton2（前进）。左/右鼠标键不录制，保留设置和退出操作。")
    save := window.AddButton("w90", "保存")
    save.OnEvent("Click", SaveSettings)
    cancel := window.AddButton("x+10 w90", "取消")
    cancel.OnEvent("Click", CloseKeySettings)
    window.OnEvent("Close", CloseKeySettings)
    window.OnEvent("Escape", CloseKeySettings)
    window.Show()
}

StopRecordingButton(*) {
    global RecordDisplay
    CancelKeyRecording()
    RecordDisplay.Text := "录制已停止；未修改触发键。可重新录制或取消。"
}

SaveSettings(*) {
    global TriggerKey, RecordedSpec, RecordingActive, RecordHeldVK
    global CloseKey, ProposedTriggerSpec, ProposedCloseSpec
    if RecordingActive || RecordHeldVK || !IsObject(RecordedSpec) {
        MsgBox("请完成录制并松开按键后再保存。", "语音输入设置")
        return
    }
    if !RecordedSpec.Allowed {
        MsgBox(RecordedSpec.Reason, "此键暂不支持")
        return
    }
    RememberRecordedCandidate()
    open := ProposedTriggerSpec.Key
    close := IsObject(ProposedCloseSpec) ? ProposedCloseSpec.Key : ""
    try ValidateBindingPair(open, close)
    catch as problem {
        MsgBox(problem.Message, "语音输入设置")
        return
    }
    if (open != TriggerKey || close != CloseKey) && MsgBox("唤起键：" ProposedTriggerSpec.Label
        "`n关闭键：" (IsObject(ProposedCloseSpec) ? ProposedCloseSpec.Label : "未设置")
        "`n`n鼠标键将全局占用，不同时前进/后退；无语音面板时关闭键安全无操作。确认保存？", "确认修改", "YesNo Default2") != "Yes"
        return
    try SaveBindingPair(open, close)
    catch as problem {
        MsgBox("保存失败，保留原触发键。`n" problem.Message, "语音输入设置")
        return
    }
    A_IconTip := "语音输入：运行中，触发键 " ResolveKeySpec(TriggerKey).Label
    WriteMappingStatus(true)
    CloseKeySettings()
}

CloseKeySettings(*) {
    global SettingsOpen, SettingsWindow, Snapshot, SnapshotTick
    CancelKeyRecording()
    SettingsWindow.Destroy()
    Snapshot := 0, SnapshotTick := 0
    SettingsOpen := false
}
