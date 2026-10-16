#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError((problem, *) => (FileAppend(problem.Message "`n" problem.Stack, "**"), ExitApp(1)))
#Include KeyCatalog.ahk
#Include KeyboardObserver.ahk
#Include GlobalModifierTap.ahk
#Include GlobalRuntime.ahk
global SettingsOpen := false, SettingsWindow := 0, Held := false, NativeHeld := false
global StopRequest := A_ScriptDir "\test-unused-stop.request", Count := 0, Passed := 0
global TriggerKey := "RShift"
VoiceDispatchSink := RecordCounter
RecordCounter() {
    global Count
    Count += 1
}
BindingSpec := ResolveKeySpec("RShift")
Check(ok, label) {
    global Passed
    if !ok
        throw Error(label)
    Passed += 1
}
; Exhaustive press predicate; no foreground or provider input exists.
Loop 64 {
    bits := A_Index - 1
    injected := !!(bits & 1), down := !!(bits & 2), settings := !!(bits & 4)
    modifiers := !!(bits & 8), native := !!(bits & 16), held := !!(bits & 32)
    expected := !injected && down && !settings && (held || (!native && !modifiers))
    Check(GlobalPressAllowed(injected, down, settings, modifiers, native, held) = expected, "press predicate " bits)
}
Loop 64 {
    bits := A_Index - 1
    p := !!(bits & 1), s := !!(bits & 2), d := !!(bits & 4)
    c := !!(bits & 8), m := !!(bits & 16), k := !!(bits & 32)
    Check(ModifierTapAllowed(p,s,d,c,m,k) = (p && !s && !d && !c && !m && !k), "tap predicate " bits)
}
Tap(combo := false, injected := false, repeats := 0) {
    global BindingSpec
    ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, true, injected)
    ModifierPressed()
    Loop repeats
        ModifierPressed()
    if combo
        ObserveKeyboardMetadata(0x41, 0x1E, true, false)
    ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, false, injected)
    ModifierReleased()
}
Tap(false, false, 5)
Sleep(35)
Check(Count = 1, "repeat yields exactly one")
Tap(true)
Sleep(35)
Check(Count = 1, "Shift combination suppressed")
Tap(false, true)
Sleep(35)
Check(Count = 1, "injected event ignored")
SettingsOpen := true
Tap()
Sleep(35)
Check(Count = 1, "settings pause")
SettingsOpen := false
Loop 10
    Tap()
Sleep(35)
Check(Count = 11, "rapid independent releases counted")
Check(!NativeHeld && !SelectedPhysicalDown && !IsObject(ModifierPending), "no held state after release")
Tap()
SettingsOpen := true
Sleep(35)
Check(Count = 11 && PendingTapCount = 0, "settings cancels queued tap")
SettingsOpen := false
; Decode side Shift metadata without installing any hook or injecting keys.
Loop 2 {
    vk := A_Index = 1 ? 0xA0 : 0xA1
    sc := A_Index = 1 ? 0x2A : 0x36
    buf := Buffer(24, 0)
    NumPut("UInt", 0x10, "UInt", sc, "UInt", 0, buf)
    decoded := DecodeKeyboardEvent(0x100, buf)
    Check(decoded.VK = vk && decoded.Down && !decoded.Injected, "side shift decode")
}
Check(!RecoveryActive(), "no selected-key synthesis")
; Exercise the real ordinary-key handler with metadata and counter only.
BindingSpec := ResolveKeySpec("A")
Held := true
TriggerVoice()
Check(Count = 11, "ordinary repeat handler ignored while held")
Held := false
ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, true, false)
SetTimer((*) => ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, false, false), -25)
TriggerVoice()
Check(Count = 12 && !Held && !SelectedPhysicalDown, "ordinary held press dispatches once and releases")
SettingsOpen := true
ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, true, false)
Check(!GateReady(), "ordinary settings pass-through predicate")
SetTimer((*) => ObserveKeyboardMetadata(BindingSpec.VK, BindingSpec.SC, false, false), -25)
TriggerVoice()
Check(Count = 12 && !Held, "ordinary paused handler dispatches zero")
SettingsOpen := false
result := FileOpen(A_ScriptDir "\global-mapping-unit-results.json", "w", "UTF-8")
result.Write('{"passed":' Passed ',"voice_dispatch_counter":' Count ',"actual_send_calls":0,"hooks_installed":false,"microphone_used":false}')
result.Close()
ExitApp()
LogGateEvent(*) {
}
