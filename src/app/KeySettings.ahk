#Include CloseBindings.ahk
global OpenBindingLabel := 0, CloseBindingLabel := 0
global SettingsControls := Map()
BindTriggerKey(key, enabled) {
    global InputState, CloseBindingSpec, SmokeTest
    if !enabled
        return
    spec := ResolveKeySpec(key)
    if !IsObject(InputState)
        InputState := BindingInputRouter(spec, CloseBindingSpec)
    else
        InputState.Configure(spec, CloseBindingSpec)
    if !SmokeTest {
        for vk in [0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0x5B,0x5C]
            InputState.SeedModifier(vk, !!(DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000))
        for selected in [spec, CloseBindingSpec]
            if IsObject(selected) && !selected.Pulse && BoundSpecPhysicallyDown(selected)
                InputState.Held[(selected.Mouse ? "m" : "k") ":" selected.VK ":" selected.SC] := {Consume: false}
        StartKeyboardObserver()
    }
}
UpdateSettingLabels() {
    global OpenBindingLabel, CloseBindingLabel, ProposedTriggerSpec, ProposedCloseSpec
    if IsObject(OpenBindingLabel)
        OpenBindingLabel.Text := "打开：" SettingsKeyLabel(ProposedTriggerSpec)
    if IsObject(CloseBindingLabel)
        CloseBindingLabel.Text := "关闭：" (IsObject(ProposedCloseSpec) ? SettingsKeyLabel(ProposedCloseSpec) : "未设置")
}
SettingsKeyLabel(spec) {
    label := RegExReplace(spec.Label, "（[A-Za-z0-9_]+）$", "")
    return StrReplace(label, "鼠标侧键 ", "侧键")
}
OpenKeySettings(*) {
    global SettingsOpen, SettingsWindow, TriggerKey, CloseKey, InputState, RecoveryPaused
    global RecordedSpec, ProposedTriggerSpec, ProposedCloseSpec, RecordingTarget
    global RecordDisplay, RecordButton, OpenRecordButton, CloseRecordButton, RecordCaptureControl, OpenBindingLabel, CloseBindingLabel
    if SettingsOpen {
        SettingsWindow.Show()
        return
    }
    SettingsOpen := true
    if IsObject(InputState)
        InputState.Pause()
    ProposedTriggerSpec := ResolveKeySpec(TriggerKey), ProposedCloseSpec := CloseKey = "" ? 0 : ResolveKeySpec(CloseKey)
    RecordedSpec := ProposedTriggerSpec, RecordingTarget := "open"
    window := CreateSettingsWindow()
    size := SettingsInitialSize()
    window.Show("w" size.W " h" size.H)
}
; Shared by the real dialog and its non-interactive layout checks.
CreateSettingsWindow() {
    global SettingsWindow, SettingsControls, RecoveryPaused
    global OpenBindingLabel, CloseBindingLabel, OpenRecordButton, CloseRecordButton, RecordButton, RecordDisplay, RecordCaptureControl
    window := Gui("+Resize", "语音输入设置"), SettingsWindow := window
    window.SetFont("s10", "Microsoft YaHei UI")
    SettingsControls := Map()
    SettingsControls["intro"] := window.AddText("x16 y16 w580 h44", RecoveryPaused
        ? "当前为紧急暂停。保存后才会恢复；取消或关闭会继续暂停。"
        : "设置中快捷键暂停，取消恢复原绑定。`n同键：面板未开就打开，已开就关闭。")
    OpenBindingLabel := window.AddText("x16 y68 w280 h26", "")
    CloseBindingLabel := window.AddText("x312 y68 w280 h26", "")
    OpenRecordButton := window.AddButton("x16 y100 w280 h32", "录制打开键")
    OpenRecordButton.OnEvent("Click", BeginOpenKeyRecording)
    CloseRecordButton := window.AddButton("x312 y100 w280 h32", "录制关闭键")
    CloseRecordButton.OnEvent("Click", BeginCloseKeyRecording)
    RecordButton := OpenRecordButton
    stop := window.AddButton("x16 y144 w110 h30", "停止录制")
    stop.OnEvent("Click", StopRecordingButton)
    SettingsControls["steps"] := window.AddText("x138 y144 w454 h38", "先选录制，再按下并松开单键。`n鼠标用下方区域；Esc 停止。")
    SettingsControls["steps"].SetFont("s9")
    RecordDisplay := window.AddText("x16 y190 w580 h44", "尚未录制。更改后需点击“保存启用”；取消不改原绑定。")
    RecordDisplay.SetFont("s9")
    RecordCaptureControl := window.AddText("x16 y246 w580 h208 +Border +0x200 Center", "鼠标按键 / 滚轮录制区`n先选上方录制，再在此点击或滚动")
    SettingsControls["warning"] := window.AddText("x16 y466 w580 h32", "注意：绑定会占用这个键原来的输入功能。")
    defaults := window.AddButton("x16 y510 w130 h34", "恢复默认")
    defaults.OnEvent("Click", RestoreDefaultBindings)
    help := window.AddButton("x158 y510 w130 h34", "使用说明")
    help.OnEvent("Click", ShowSettingsHelp)
    save := window.AddButton("x300 y510 w142 h34", "保存启用")
    save.OnEvent("Click", SaveSettings)
    cancel := window.AddButton("x454 y510 w142 h34", "取消更改")
    cancel.OnEvent("Click", CloseKeySettings)
    for name, control in Map("openLabel",OpenBindingLabel,"closeLabel",CloseBindingLabel,"open",OpenRecordButton,"close",CloseRecordButton,
        "stop",stop,"status",RecordDisplay,"capture",RecordCaptureControl,"defaults",defaults,"help",help,"save",save,"cancel",cancel)
        SettingsControls[name] := control
    window.OnEvent("Close", CloseKeySettings), window.OnEvent("Escape", SettingsEscape)
    window.OnEvent("Size", ResizeSettings)
    UpdateSettingLabels()
    size := SettingsInitialSize()
    window.Opt("+MinSize360x320")
    ResizeSettings(window, 0, size.W, size.H)
    return window
}
SettingsInitialSize() {
    MonitorGetWorkArea(, &left, &top, &right, &bottom)
    scale := A_ScreenDPI / 96
    return {W: Max(360, Min(640, Floor((right-left)/scale)-32)), H: Max(320, Min(640, Floor((bottom-top)/scale)-64))}
}
SettingsLayout(width, height) {
    margin := 16, gap := 12, inner := width-2*margin, half := Floor((inner-gap)/2)
    compact := height < 520
    footerY := height-50, warningY := footerY-42, captureY := compact ? 218 : 246
    buttonW := Floor((inner-3*gap)/4)
    if height < 400 {
        footerY := height-44, warningY := footerY-34, captureY := 194
        return Map("intro",[margin,8,inner,24],"openLabel",[margin,40,half,26],"closeLabel",[margin+half+gap,40,half,26],
            "open",[margin,72,half,30],"close",[margin+half+gap,72,half,30],"stop",[margin,110,104,30],
            "steps",[margin+116,108,inner-116,36],"status",[margin,150,inner,36],
            "capture",[margin,captureY,inner,warningY-captureY-8],"warning",[margin,warningY,inner,26],
            "defaults",[margin,footerY,buttonW,30],"help",[margin+buttonW+gap,footerY,buttonW,30],
            "save",[margin+2*(buttonW+gap),footerY,buttonW,30],"cancel",[margin+3*(buttonW+gap),footerY,inner-3*(buttonW+gap),30])
    }
    return Map("intro",[margin,compact ? 8 : 16,inner,40],"openLabel",[margin,compact ? 54 : 68,half,26],"closeLabel",[margin+half+gap,compact ? 54 : 68,half,26],
        "open",[margin,compact ? 84 : 100,half,32],"close",[margin+half+gap,compact ? 84 : 100,half,32],"stop",[margin,compact ? 126 : 144,104,34],
        "steps",[margin+116,compact ? 124 : 140,inner-116,40],"status",[margin,compact ? 170 : 190,inner,40],
        "capture",[margin,captureY,inner,Max(64,warningY-captureY-12)],"warning",[margin,warningY,inner,34],
        "defaults",[margin,footerY,buttonW,34],"help",[margin+buttonW+gap,footerY,buttonW,34],
        "save",[margin+2*(buttonW+gap),footerY,buttonW,34],"cancel",[margin+3*(buttonW+gap),footerY,inner-3*(buttonW+gap),34])
}
ResizeSettings(window, minMax, width, height) {
    global SettingsControls, RecoveryPaused
    if minMax = -1
        return
    SettingsControls["intro"].Text := height < 400
        ? (RecoveryPaused ? "紧急暂停中；保存才恢复，取消仍暂停。" : "设置期间暂停；取消不改原设置。")
        : (RecoveryPaused ? "当前为紧急暂停。保存后才会恢复；取消或关闭会继续暂停。"
            : "设置中快捷键暂停，取消恢复原绑定。`n同键：面板未开就打开，已开就关闭。")
    for name, bounds in SettingsLayout(width, height)
        SettingsControls[name].Move(bounds*)
}
SettingsEscape(*) {
    global RecordingActive, RecordHeldVK
    if RecordingActive || RecordHeldVK
        StopRecordingButton()
    else
        CloseKeySettings()
}
ShowSettingsHelp(*) {
    CancelKeyRecording()
    MsgBox("设置步骤`n1. 选择“录制打开键”或“录制关闭键”。`n2. 键盘：按下并松开一个键；不支持组合键。鼠标：只在大录制区内点击或滚动。10 秒未操作会停止。`n3. 录到的内容先是草稿；点击“保存启用”，确认后才生效。取消、关闭窗口都保留原绑定。`n`n打开与关闭`n可以设置两个不同的键，也可以设为同一个键；同键会按面板是否打开来切换。`n`n停止和退出`n录制时按 Esc 或点“停止录制”；再按一次 Esc 可取消设置。窗口以外及保存、取消等按钮不属于鼠标录制区。`n`n暂停与恢复`n打开设置会暂停快捷键。正常取消会恢复原绑定；若已用 Ctrl+Alt+Shift+F12 紧急暂停，取消后仍暂停，保存才恢复。恢复默认只选中后退侧键打开、前进侧键关闭，还需保存。`n`n注意`n普通字母、左/右鼠标键或滚轮被绑定后，原功能会被占用。建议优先用侧键或不常用的键。Fn 和系统保留的按键可能无法录制。Esc 在设置内用于停止/退出，不参与录制。", "使用说明", "Iconi")
}
RestoreDefaultBindings(*) {
    global ProposedTriggerSpec, ProposedCloseSpec, RecordedSpec, RecordDisplay
    CancelKeyRecording()
    ProposedTriggerSpec := ResolveKeySpec("XButton1"), ProposedCloseSpec := ResolveKeySpec("XButton2"), RecordedSpec := ProposedTriggerSpec
    UpdateSettingLabels()
    RecordDisplay.Text := "已选择默认：后退侧键打开、前进侧键关闭。点击保存应用；取消不改变现有绑定。"
}
StopRecordingButton(*) {
    global RecordDisplay
    CancelKeyRecording()
    RecordDisplay.Text := "录制已停止；可以保存已有选择、恢复默认或取消。"
}
SaveSettings(*) {
    global RecordingActive, RecordHeldVK, ProposedTriggerSpec, ProposedCloseSpec, RecoveryPaused
    if RecordingActive || RecordHeldVK {
        global RecordDisplay
        RecordDisplay.Text := "请先停止录制并松开按键，再保存。也可取消更改。"
        return
    }
    close := IsObject(ProposedCloseSpec) ? ProposedCloseSpec.Key : ""
    pair := ValidateBindingPair(ProposedTriggerSpec.Key, close)
    text := "打开：" pair.Open.Label "`n关闭：" (IsObject(pair.Close) ? pair.Close.Label : "未设置")
        . "`n" (pair.Shared ? "同一绑定：按实际面板是否存在来打开或真正关闭。" : "不同绑定分别打开和关闭。")
        . "`n`n绑定会占用原点击、滚动或打字功能；设置中暂停。Ctrl+Alt+Shift+F12 可紧急暂停并打开设置，恢复默认后保存。确认保存并恢复映射？"
    text .= "`n`n" KeyOccupancyWarning(pair.Open)
    if IsObject(pair.Close)
        text .= "`n" KeyOccupancyWarning(pair.Close)
    if MsgBox(text, "确认绑定占用", "YesNo Default2") != "Yes"
        return
    try SaveBindingPair(pair.Open.Key, close)
    catch as problem {
        MsgBox(problem.Message, "保存失败：保留原绑定")
        return
    }
    RecoveryPaused := false
    UpdateMappingTooltip()
    SupportLog("saved", "open=" pair.Open.Key " close=" close)
    WriteMappingStatus(true)
    CloseKeySettings()
}
CloseKeySettings(*) {
    global SettingsOpen, SettingsWindow, InputState
    CancelKeyRecording()
    if IsObject(SettingsWindow)
        SettingsWindow.Destroy()
    SettingsOpen := false
    if IsObject(InputState)
        InputState.Pause()
}
