#Requires AutoHotkey v2.0
#Include RuntimeState.ahk
#Include KeyCatalog.ahk
; A read-only status viewer must not acquire the application's single-instance mutex.
DataDir := EnvGet("WIN_VOICE_HOTKEY_DATA_DIR")
if DataDir = ""
    DataDir := A_AppData "\WinVoiceHotkey"
state := DataDir "\mapping-state.ini"
values := Map()
try values := ParseRuntimeState(ReadRuntimeFile(state))
pid := values.Get("PID","0")
window := values.Get("HWND","0")
token := values.Get("InstanceToken","0")
windowPid := 0
if window != "0"
    DllCall("GetWindowThreadProcessId", "Ptr", window, "UInt*", &windowPid)
running := values.Get("Running","0") = "1" && values.Get("Ready","0") = "1" && pid != "0" && ProcessExist(pid)
    && windowPid = pid && token != "0"
    && DllCall("GetPropW", "Ptr", window, "WStr", "WinVoiceHotkeyInstance", "Ptr") = token
mode := values.Get("Mode","stopped")
key := values.Get("Key","XButton1")
try key := ResolveKeySpec(key).Label
message := running ? (mode = "global_voice_mapping" ? "全局语音映射正在运行，无需输入框判断。独立按键触发 Win+H，设置中暂停，退出后解除映射。" : "安全诊断正在运行，不调用语音。") : "已停止，没有运行中的映射。"
closeKey := values.Get("CloseKey","")
closeLabel := "未设置"
if closeKey != "" {
    try closeLabel := ResolveKeySpec(closeKey).Label
}
closeResult := values.Get("CloseResult","not_requested")
statusLabels := Map("not_requested", "尚未请求关闭", "closed_verified", "面板已确认消失", "panel_absent", "没有可识别的语音面板，未操作", "identity_unknown", "面板身份未确认，未操作", "button_missing", "未找到可靠关闭按钮，未操作", "close_not_verified", "已请求关闭，但未确认面板消失", "helper_timeout_no_other_action", "关闭检查超时，未操作其他窗口", "pending", "正在检查语音面板")
statusLabels["closed"] := "语音面板已关闭"
statusLabels["no_verified_panel"] := "未识别到语音面板，未执行关闭"
statusLabels["ambiguous_panel"] := "检测结果不明确，未执行关闭"
statusLabels["rejected"] := "窗口检查未通过，未执行关闭"
statusLabels["changed_before_close"] := "面板状态已改变，未执行关闭"
statusLabels["close_not_confirmed"] := "已尝试关闭，但未确认面板消失"
statusLabels["tracker_unavailable"] := "关闭键暂不可用，打开键仍可使用"
statusLabels["helper_not_ready"] := "关闭键暂不可用，可退出后重新启动语音输入"
statusLabels["helper_start_failed"] := "关闭键启动失败，打开键仍可使用"
statusLabels["helper_busy"] := "正在处理关闭操作"
closeDescription := statusLabels.Has(closeResult) ? statusLabels[closeResult] : "关闭检查未完成，未操作其他窗口"
MsgBox(message "`n唤起键：" key "`n关闭键：" closeLabel "`n关闭结果：" closeDescription "`n关闭键无面板时不操作，不执行前进/后退。`n右键托盘图标选择退出可解除映射。", "语音输入状态")
ExitApp()
