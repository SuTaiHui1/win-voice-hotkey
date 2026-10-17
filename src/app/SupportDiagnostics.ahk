; Opt-in support diagnostics for this candidate only. No input text or window titles.
global SupportDiagnostics := EnvGet("WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS") = "1"
SupportLog(event, details := "") {
    global SupportDiagnostics, DataDir
    if !SupportDiagnostics
        return
    path := DataDir "\support-diagnostics.log"
    try {
        if FileExist(path) && FileGetSize(path) > 131072
            return
        FileAppend(A_NowUTC " " event " " details "`n", path, "UTF-8-RAW")
    }
}
UpdateMappingTooltip() {
    global TriggerKey, CloseKey
    open := ResolveKeySpec(TriggerKey), close := CloseKey = "" ? 0 : ResolveKeySpec(CloseKey)
    A_IconTip := "语音输入：" (IsObject(close) && open.Key = close.Key ? "同键开/关 " open.Label
        : "打开 " open.Label "；关闭 " (IsObject(close) ? close.Label : "未设置"))
}
