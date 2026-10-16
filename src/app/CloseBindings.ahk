; The independent close action is deliberately limited to standard mouse buttons.
global RecordingTarget := "open", ProposedTriggerSpec := 0, ProposedCloseSpec := 0
global CloseRecordButton := 0, OpenRecordButton := 0

ValidateBindingPair(openKey, closeKey) {
    open := ResolveKeySpec(openKey)
    if !KeyAllowedForBinding(open)
        throw Error(open.Reason)
    close := closeKey = "" ? 0 : ResolveKeySpec(closeKey)
    if IsObject(close) && (!close.Mouse || !close.Allowed)
        throw Error("关闭键仅支持鼠标中键、XButton1 或 XButton2。")
    if IsObject(close) && open.Key = close.Key
        throw Error("唤起键和关闭键不能相同，请重新录制。")
    return {Open: open, Close: close}
}
LoadCloseBinding() {
    global CloseKey, CloseBindingSpec, TriggerKey, ConfigPath
    close := IniRead(ConfigPath, "Mapping", "CloseKey", "__missing__")
    if close = "__missing__" {
        close := TriggerKey = "XButton2" ? "" : "XButton2"
        IniWrite(close, ConfigPath, "Mapping", "CloseKey")
    }
    try pair := ValidateBindingPair(TriggerKey, close)
    catch {
        ; Never replace the user's working open key to resolve a conflict.
        CloseKey := "", CloseBindingSpec := 0
        return
    }
    CloseKey := IsObject(pair.Close) ? pair.Close.Key : ""
    CloseBindingSpec := pair.Close
}
PersistBindingPair(open, close) {
    global ConfigPath
    IniWrite(open, ConfigPath, "Mapping", "Key")
    IniWrite(close, ConfigPath, "Mapping", "CloseKey")
}
SaveBindingPair(open, close, persist := 0, binder := 0) {
    global TriggerKey, CloseKey, CloseBindingSpec, CloseMappedHeld, ConfigPath
    global Held, NativeHeld, RestoredDown, RecordHeldVK, MouseMappedHeld, SelectedPhysicalDown, ModifierPending
    pair := ValidateBindingPair(open, close)
    if Held || NativeHeld || RestoredDown || RecordHeldVK || MouseMappedHeld || CloseMappedHeld || SelectedPhysicalDown || IsObject(ModifierPending)
        || GetKeyState(TriggerKey, "P") || GetKeyState(pair.Open.Key, "P")
        || (CloseKey != "" && GetKeyState(CloseKey, "P"))
        || (IsObject(pair.Close) && GetKeyState(pair.Close.Key, "P"))
        throw Error("请先松开所有唤起键、关闭键和录制键，再保存。")
    oldOpen := TriggerKey, oldClose := CloseKey, oldSpec := CloseBindingSpec
    original := FileRead(ConfigPath, "RAW")
    Critical("On")
    try {
        CloseKey := "", CloseBindingSpec := 0
        SwitchTriggerKey(pair.Open.Key, (*) => 0, binder)
        CloseKey := IsObject(pair.Close) ? pair.Close.Key : ""
        CloseBindingSpec := pair.Close
        (persist ? persist : PersistBindingPair)(TriggerKey, CloseKey)
    } catch as problem {
        try {
            CloseKey := "", CloseBindingSpec := 0
            SwitchTriggerKey(oldOpen, (*) => 0, binder)
            CloseKey := oldClose, CloseBindingSpec := oldSpec
            stream := FileOpen(ConfigPath, "w")
            stream.RawWrite(original), stream.Close()
        } catch {
            ExitApp(1)
        }
        throw problem
    } finally Critical("Off")
}
RememberRecordedCandidate() {
    global RecordedSpec, RecordingTarget, ProposedTriggerSpec, ProposedCloseSpec
    if IsObject(RecordedSpec) && RecordedSpec.Allowed {
        if RecordingTarget = "close"
            ProposedCloseSpec := RecordedSpec
        else
            ProposedTriggerSpec := RecordedSpec
    }
}
BeginOpenKeyRecording(*) {
    global RecordingTarget, RecordButton, OpenRecordButton
    RememberRecordedCandidate()
    RecordingTarget := "open", RecordButton := OpenRecordButton
    BeginKeyRecording()
}
BeginCloseKeyRecording(*) {
    global RecordingTarget, RecordButton, CloseRecordButton
    RememberRecordedCandidate()
    RecordingTarget := "close", RecordButton := CloseRecordButton
    BeginKeyRecording()
}
