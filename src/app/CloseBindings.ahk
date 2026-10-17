global ProposedTriggerSpec := 0, ProposedCloseSpec := 0, OpenRecordButton := 0, CloseRecordButton := 0
ValidateBindingPair(openKey, closeKey) {
    open := ResolveKeySpec(openKey), close := closeKey = "" ? 0 : ResolveKeySpec(closeKey)
    if !KeyAllowedForBinding(open) || (IsObject(close) && !KeyAllowedForBinding(close))
        throw Error("请选择 Windows 能上报的一个键盘键、鼠标键或滚轮方向。")
    return {Open: open, Close: close, Shared: IsObject(close) && open.Key = close.Key}
}
LoadCloseBinding() {
    global CloseKey, CloseBindingSpec, TriggerKey, ConfigPath
    close := IniRead(ConfigPath, "Mapping", "CloseKey", "__missing__")
    if close = "__missing__" {
        close := TriggerKey = "XButton2" ? "" : "XButton2"
        IniWrite(close, ConfigPath, "Mapping", "CloseKey")
    }
    pair := ValidateBindingPair(TriggerKey, close)
    TriggerKey := pair.Open.Key, CloseKey := IsObject(pair.Close) ? pair.Close.Key : "", CloseBindingSpec := pair.Close
}
PersistBindingPair(open, close) {
    global ConfigPath
    IniWrite(open, ConfigPath, "Mapping", "Key")
    IniWrite(close, ConfigPath, "Mapping", "CloseKey")
}
BoundSpecPhysicallyDown(spec) {
    return IsObject(spec) && !spec.Wheel && (DllCall("GetAsyncKeyState", "Int", spec.VK, "Short") & 0x8000)
}
SaveBindingPair(open, close, persist := 0, binder := 0) {
    global TriggerKey, CloseKey, CloseBindingSpec, ConfigPath, InputState, RecordHeldVK, ActionState
    pair := ValidateBindingPair(open, close)
    oldOpen := ResolveKeySpec(TriggerKey), oldClose := CloseBindingSpec
    if RecordHeldVK || (IsObject(InputState) && InputState.HasHeld())
        || BoundSpecPhysicallyDown(pair.Open) || BoundSpecPhysicallyDown(pair.Close)
        || BoundSpecPhysicallyDown(oldOpen) || BoundSpecPhysicallyDown(oldClose)
        throw Error("请先松开新旧绑定及录制中的按键，再保存。")
    original := FileRead(ConfigPath, "RAW")
    try {
        (persist ? persist : PersistBindingPair)(pair.Open.Key, IsObject(pair.Close) ? pair.Close.Key : "")
        if IsObject(binder)
            binder.Call(pair.Open.Key, true)
        TriggerKey := pair.Open.Key, CloseKey := IsObject(pair.Close) ? pair.Close.Key : "", CloseBindingSpec := pair.Close
        if IsObject(InputState)
            InputState.Configure(pair.Open, pair.Close)
        ActionState := PanelActionState()
    } catch as problem {
        stream := FileOpen(ConfigPath, "w")
        try stream.RawWrite(original)
        finally stream.Close()
        TriggerKey := oldOpen.Key, CloseKey := IsObject(oldClose) ? oldClose.Key : "", CloseBindingSpec := oldClose
        if IsObject(InputState)
            InputState.Configure(oldOpen, oldClose)
        throw problem
    }
}
BeginOpenKeyRecording(*) {
    global RecordingTarget, RecordButton, OpenRecordButton
    RecordingTarget := "open", RecordButton := OpenRecordButton
    BeginKeyRecording()
}
BeginCloseKeyRecording(*) {
    global RecordingTarget, RecordButton, CloseRecordButton
    RecordingTarget := "close", RecordButton := CloseRecordButton
    BeginKeyRecording()
}
