global PendingTapCount := 0, PendingTapDeadline := 0
ModifierPhysicalPress(injected, down, settingsOpen) => !injected && down && !settingsOpen
ModifierTapAllowed(pending, settings, physicalDown, combination, otherModifier, otherKey) =>
    pending && !settings && !physicalDown && !combination && !otherModifier && !otherKey
ModifierPressed(*) {
    global NativeHeld, SelectedEventInjected, SelectedPhysicalDown, SettingsOpen, BindingSpec, ModifierPending
    if !ModifierPhysicalPress(SelectedEventInjected, SelectedPhysicalDown, SettingsOpen) || NativeHeld
        return
    NativeHeld := true
    ModifierPending := !OtherModifierHeld(BindingSpec.VK) && !AnyOtherKeyboardKeyDown(BindingSpec.VK) ? {Started: A_TickCount} : 0
}
ModifierReleased(*) {
    global NativeHeld, SelectedEventInjected, ModifierPending, SettingsOpen, SelectedPhysicalDown, SelectedOtherKey, BindingSpec
    global PendingTapCount, PendingTapDeadline
    if SelectedEventInjected
        return
    NativeHeld := false
    pending := ModifierPending
    ModifierPending := 0
    if ModifierTapAllowed(IsObject(pending), SettingsOpen, SelectedPhysicalDown, SelectedOtherKey,
        OtherModifierHeld(BindingSpec.VK), AnyOtherKeyboardKeyDown(BindingSpec.VK)) {
        PendingTapCount += 1
        PendingTapDeadline := A_TickCount + 250
        SetTimer(FinishModifierTap, -15)
    }
}
OtherModifierHeld(selectedVK := 0) {
    for key in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin"]
        if GetKeyVK(key) != selectedVK && (GetKeyState(key, "P") || GetKeyState(key))
            return true
    return false
}
AnyOtherKeyboardKeyDown(selectedVK) {
    Loop 247 {
        vk := A_Index + 7
        ; Generic VK_SHIFT mirrors the selected side and is not another key.
        if vk = selectedVK || (vk = 0x10 && (selectedVK = 0xA0 || selectedVK = 0xA1))
            continue
        if DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000
            return true
    }
    return false
}
FinishModifierTap(*) {
    global PendingTapCount, PendingTapDeadline, SettingsOpen, SelectedPhysicalDown, BindingSpec
    if SettingsOpen || A_TickCount > PendingTapDeadline {
        PendingTapCount := 0
        return
    }
    if SelectedPhysicalDown || OtherModifierHeld() {
        SetTimer(FinishModifierTap, -15)
        return
    }
    count := PendingTapCount
    PendingTapCount := 0
    if AnyOtherKeyboardKeyDown(BindingSpec.VK)
        return
    Loop count
        DispatchVoiceRequest()
}
