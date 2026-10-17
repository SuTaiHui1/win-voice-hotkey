; Configuration is always a single safe key identifier, never hotkey syntax.
global KeyFixtureMode := false
KeySpecFromCodes(vk, sc) {
    if !UserKeyInScope(vk, sc)
        throw Error("Windows 未提供可用的物理单键标识；Fn、硬件拦截键和系统安全序列无法保证捕获。")
    if vk = 0x10
        vk := (sc & 0xFF) = 0x36 ? 0xA1 : 0xA0
    else if vk = 0x11
        vk := sc & 0x100 ? 0xA3 : 0xA2
    else if vk = 0x12
        vk := sc & 0x100 ? 0xA5 : 0xA4
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
    else if vk = 0xA4
        key := "LAlt"
    else if vk = 0xA5
        key := "RAlt"
    else if vk = 0x5B
        key := "LWin"
    else if vk = 0x5C
        key := "RWin"
    modifier := (vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C
    bindingSC := SubStr(key, 1, 2) = "vk" ? 0 : sc
    return {Key: key, VK: vk, SC: bindingSC, Name: name, Modifier: modifier, Mouse: false,
        Pulse: vk = 0x13 || vk = 0x03 || vk = 0x2C, Wheel: false,
        Allowed: true, Reason: "", Label: KeyFriendlyName(name, vk, sc)}
}

UserKeyInScope(vk, sc) {
    return (vk = 3 || (vk >= 8 && vk <= 254)) && vk != 0xE7 && sc >= 0 && sc <= 0x1FF
}

KeyAllowedForBinding(spec) {
    return IsObject(spec) && spec.Allowed
}

ResolveKeySpec(key) {
    for mouseKey in ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
        if StrLower(key) = StrLower(mouseKey)
            return MouseKeySpec(mouseKey)
    ; Named keyboard keys are accepted only after normalization to VK/SC.
    if RegExMatch(key, "i)^(sc[0-9a-f]{3}|vk[0-9a-f]{2})$") {
        sc := SubStr(key, 1, 2) = "sc" ? Integer("0x" SubStr(key, 3)) : 0
        vk := sc ? GetKeyVK(key) : Integer("0x" SubStr(key, 3))
        if !sc
            sc := GetKeySC(key)
    } else {
        if StrLen(key) > 40 || InStr(key, "::") || RegExMatch(key, "[\r\n\t]")
            throw Error("请录制一个键；不支持组合键表达式或脚本。")
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
        return "运行时会占用此键的原点击、前进/后退或滚动功能。设置窗口中暂停映射；Ctrl+Alt+Shift+F12 可暂停并打开设置，恢复默认后保存。退出程序恢复原功能。"
    if spec.Modifier
        return "修饰键保留原组合键功能，仅独立按下并松开时触发。Win/Alt 的系统行为也可能出现。Ctrl+Alt+Shift+F12 可暂停并打开设置；退出恢复。"
    return "运行时会占用此键的打字或原功能，长按仅触发一次。设置中暂停；Ctrl+Alt+Shift+F12 可暂停并打开设置，恢复默认后保存。Fn、硬件和系统安全键不保证可捕获。"
}

MouseKeySpec(key) {
    static specs := Map("LButton", [1, "鼠标左键"], "RButton", [2, "鼠标右键"],
        "MButton", [4, "鼠标中键"], "XButton1", [5, "鼠标侧键 1（后退）"], "XButton2", [6, "鼠标侧键 2（前进）"],
        "WheelUp", [256, "滚轮向上"], "WheelDown", [257, "滚轮向下"], "WheelLeft", [258, "横滚向左"], "WheelRight", [259, "横滚向右"])
    if !specs.Has(key)
        throw Error("不支持的鼠标单键或滚轮方向。")
    item := specs[key]
    return {Key: key, VK: item[1], SC: 0, Name: key, Modifier: false, Mouse: true,
        Pulse: item[1] >= 256, Wheel: item[1] >= 256, Allowed: true, Reason: "", Label: item[2] "（" key "）"}
}
