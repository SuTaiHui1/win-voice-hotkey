; Configuration is always a single safe key identifier, never hotkey syntax.
global KeyFixtureMode := false
KeySpecFromCodes(vk, sc) {
    if vk < 8 || vk > 254 || vk = 0xE7 || sc < 0 || sc > 0x1FF
        throw Error("不是可绑定的键盘单键。鼠标、文字注入与组合键不支持。")
    ; AHK uses 136 as an internal Right-Shift identifier; native scan is 36.
    if vk = 0xA1 && sc
        sc := 0x036
    key := sc && GetKeyVK(Format("sc{:03X}", sc)) ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
    name := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if vk = 0x14
        key := "CapsLock"
    else if vk >= 0x70 && vk <= 0x87
        key := "F" (vk - 0x6F)
    else if vk = 0xA0
        key := "LShift"
    else if vk = 0xA1
        key := "RShift"
    else if vk = 0xA2
        key := "LCtrl"
    else if vk = 0xA3
        key := "RCtrl"
    modifier := vk = 0xA0 || vk = 0xA1
    reason := ""
    if vk = 0x12 || vk = 0xA4 || vk = 0xA5 || vk = 0x5B || vk = 0x5C
        reason := "Alt/Win 会打开系统菜单或改变焦点；为保留原组合键，当前不允许绑定。"
    else if vk = 0x10 || vk = 0x11
        reason := "请录制明确的左侧或右侧 Ctrl/Shift。"
    else if vk = 0x13 || vk = 0x03
        reason := "Pause/Break 的释放事件不可靠，不能保证按下/释放成对。"
    else if vk = 0x5F
        reason := "休眠等系统电源键不能保证安全拦截。"
    else if !UserKeyInScope(vk, sc)
        reason := "此键不在当前可选范围。支持 A–Z、0–9、标点/符号及小键盘数字/运算符、左右 Shift、CapsLock、Tab。"
    bindingSC := SubStr(key, 1, 2) = "vk" ? 0 : sc
    return {Key: key, VK: vk, SC: bindingSC, Name: name, Modifier: modifier, Mouse: false,
        Allowed: reason = "", Reason: reason, Label: KeyFriendlyName(name, vk, sc)}
}

UserKeyInScope(vk, sc) {
    ; NumLock-off navigation VKs are still the same physical numpad keys.
    numpad := sc >= 0x47 && sc <= 0x53
    return (vk >= 0x41 && vk <= 0x5A) || (vk >= 0x30 && vk <= 0x39)
        || (vk >= 0x60 && vk <= 0x69) || (vk >= 0x6A && vk <= 0x6F)
        || (vk >= 0xBA && vk <= 0xC0) || (vk >= 0xDB && vk <= 0xDF) || vk = 0xE2
        || numpad || vk = 0xA0 || vk = 0xA1 || vk = 0x14 || vk = 0x09
}

KeyAllowedForBinding(spec) {
    global KeyFixtureMode
    ; F24 is only an internal diagnostic transport, never a settings option.
    return spec.Allowed || (KeyFixtureMode && spec.Key = "F24")
}

ResolveKeySpec(key) {
    for mouseKey in ["MButton", "XButton1", "XButton2"]
        if StrLower(key) = StrLower(mouseKey)
            return MouseKeySpec(mouseKey)
    ; Named keyboard keys are accepted only after normalization to VK/SC.
    if RegExMatch(key, "i)^(sc[0-9a-f]{3}|vk[0-9a-f]{2})$") {
        sc := SubStr(key, 1, 2) = "sc" ? Integer("0x" SubStr(key, 3)) : 0
        vk := sc ? GetKeyVK(key) : Integer("0x" SubStr(key, 3))
    } else {
        if !RegExMatch(key, "i)^(CapsLock|F(?:[1-9]|1[0-9]|2[0-4])|[a-z0-9]|Enter|Escape|Space|Tab|Backspace|Delete|Insert|Home|End|PgUp|PgDn|Up|Down|Left|Right|NumLock|ScrollLock|Numpad(?:[0-9]|Dot|Div|Mult|Add|Sub|Enter)|LCtrl|RCtrl|LControl|RControl|LShift|RShift|LAlt|RAlt|LWin|RWin|AppsKey|PrintScreen|Pause|CtrlBreak|Sleep|Help|Browser_[A-Za-z]+|Volume_[A-Za-z]+|Media_[A-Za-z_]+|Launch_[A-Za-z0-9]+)$")
            throw Error("不支持此键名。请点击录制按键并按一个键盘键。")
        vk := GetKeyVK(key), sc := GetKeySC(key)
    }
    return KeySpecFromCodes(vk, sc)
}

SupportedTriggerKey(key) {
    try return ResolveKeySpec(key).Allowed
    catch
        return false
}

KeyFriendlyName(name, vk, sc) {
    static names := Map("CapsLock", "大写锁定", "NumLock", "数字锁定", "ScrollLock", "滚动锁定",
        "Space", "空格", "Tab", "制表键", "Enter", "回车", "Escape", "退出键", "Backspace", "退格",
        "Delete", "删除", "Insert", "插入", "Home", "行首", "End", "行尾", "PgUp", "上一页", "PgDn", "下一页",
        "Up", "上箭头", "Down", "下箭头", "Left", "左箭头", "Right", "右箭头", "LCtrl", "左 Ctrl",
        "RCtrl", "右 Ctrl", "LControl", "左 Ctrl", "RControl", "右 Ctrl", "LShift", "左 Shift", "RShift", "右 Shift",
        "LAlt", "左 Alt", "RAlt", "右 Alt", "LWin", "左 Win", "RWin", "右 Win", "AppsKey", "菜单键",
        "PrintScreen", "截图键", "Pause", "暂停键", "CtrlBreak", "中断键", "Sleep", "休眠键",
        "Volume_Up", "音量增加", "Volume_Down", "音量降低", "Volume_Mute", "静音",
        "Media_Next", "下一曲", "Media_Prev", "上一曲", "Media_Stop", "停止播放", "Media_Play_Pause", "播放/暂停",
        "Browser_Back", "浏览器后退", "Browser_Forward", "浏览器前进", "Browser_Refresh", "浏览器刷新",
        "Browser_Stop", "浏览器停止", "Browser_Search", "浏览器搜索", "Browser_Favorites", "浏览器收藏", "Browser_Home", "浏览器主页")
    friendly := names.Has(name) ? names[name] : RegExMatch(name, "i)^[a-z]$") ? "字母 " StrUpper(name)
        : RegExMatch(name, "^[0-9]$") ? "数字 " name : InStr(name, "Numpad") = 1 ? "小键盘 " SubStr(name, 7)
        : name != "" ? name : "特殊键"
    symbols := KeySymbols(vk, sc)
    return friendly "（" (name != "" ? name "; " : "") Format("VK {:02X} / SC {:03X}", vk, sc) "）" (symbols != "" ? "；" symbols : "")
}

KeySymbols(vk, sc) {
    if !UserKeyInScope(vk, sc) || vk = 0xA0 || vk = 0xA1 || vk = 0x14 || vk = 0x09
        return ""
    ; Translate a synthetic state buffer, never text from a real input field.
    ; Flag 4 preserves the Windows 10+ keyboard dead-key state.
    layout := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr")
    symbols := []
    Loop 2 {
        state := Buffer(256, 0), output := Buffer(32, 0)
        if A_Index = 2
            NumPut("UChar", 0x80, state, 0x10)
        NumPut("UChar", 1, state, 0x90)
        count := DllCall("ToUnicodeEx", "UInt", vk, "UInt", sc & 0xFF, "Ptr", state,
            "Ptr", output, "Int", 16, "UInt", 4, "Ptr", layout, "Int")
        symbol := count != 0 ? StrGet(output, Abs(count), "UTF-16") : ""
        if symbol != "" && Ord(symbol) < 32
            symbol := ""
        symbols.Push(symbol)
    }
    return symbols[1] != "" || symbols[2] != "" ? "主符号「" symbols[1] "」/ Shift 符号「" symbols[2] "」" : ""
}

KeyOccupancyWarning(spec) {
    if spec.Mouse
        return "程序运行期间，此鼠标键被全局占用，前进/后退或中键原功能不会同时执行；按住只触发一次 Win+H。设置中恢复原功能，退出程序后解除占用。只支持单键，不支持组合键。"
    if spec.Modifier
        return "Shift 原功能保留，独立按下并松开时全局触发 Win+H；组合键不触发。Windows 语音面板控制录音。退出本程序后解除映射。"
    return "程序运行期间，此键在所有窗口的字符或原功能会被语音快捷键占用，按住只触发一次；设置中暂停映射。退出后恢复原功能。请确认你接受全局占用。"
}

MouseKeySpec(key) {
    static specs := Map("MButton", [4, "鼠标中键"], "XButton1", [5, "鼠标侧键 1（后退）"], "XButton2", [6, "鼠标侧键 2（前进）"])
    if !specs.Has(key)
        throw Error("仅支持鼠标中键、XButton1 和 XButton2；左/右键保留用于设置和退出。")
    item := specs[key]
    return {Key: key, VK: item[1], SC: 0, Name: key, Modifier: false, Mouse: true,
        Allowed: true, Reason: "", Label: item[2] "（" key "）"}
}
