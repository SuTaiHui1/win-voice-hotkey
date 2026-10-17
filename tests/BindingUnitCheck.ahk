#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError(Failed)
#Include KeyCatalog.ahk
#Include SupportDiagnostics.ahk
#Include InputRouter.ahk
#Include KeyboardObserver.ahk
#Include GlobalRuntime.ahk
#Include KeySettings.ahk
#Include CloseBrokerRuntime.ahk
global Passed := 0, SettingsOpen := false, SettingsWindow := 0, SmokeTest := true
global DataDir := A_ScriptDir, ConfigPath := A_ScriptDir "\binding-test.ini", TriggerKey := "XButton1"
global StopRequest := A_ScriptDir "\unused-stop.request", StatusToken := 1
Check(ok, label) {
    global Passed
    if !ok
        throw Error(label)
    Passed += 1
}
Failed(problem, *) {
    FileAppend(problem.Message "`n" problem.Stack, "**")
    ExitApp(1)
}
WriteMappingStatus(*) {
}
global TrialOpenCount := 0
CountTrialOpen(*) {
    global TrialOpenCount
    TrialOpenCount += 1
}
global TestLiveFrames := Map(), TestDiscoveredFrames := [], TestScanFailure := false
RecheckTestFrame(hwnd, *) {
    global TestLiveFrames, PanelCandidates
    if TestLiveFrames.Has(hwnd)
        PanelCandidates[hwnd] := TestLiveFrames[hwnd]
}
DiscoverTestFrames(*) {
    global TestDiscoveredFrames, TestScanFailure, PanelScanComplete
    for hwnd in TestDiscoveredFrames
        RecheckTestFrame(hwnd)
    if TestScanFailure
        PanelScanComplete := false
}
FakeBind(*) {
}
FailBind(*) {
    throw Error("expected binding failure")
}
PartialPersist(open, close) {
    PersistBindingPair(open, close)
    throw Error("expected partial write failure")
}
for key in ["a","1","Tab","Space","Enter","Escape","Backspace","Delete","Insert","Home","End","PgUp","PgDn","Up","Down","Left","Right","CapsLock","NumLock","ScrollLock","Numpad0","NumpadEnter","F1","F12","F24","LCtrl","RCtrl","LShift","RShift","LAlt","RAlt","LWin","RWin","AppsKey","PrintScreen","Pause","Volume_Up","Media_Play_Pause","Browser_Back","LButton","RButton","MButton","XButton1","XButton2","WheelUp","WheelDown","WheelLeft","WheelRight"] {
    spec := ResolveKeySpec(key)
    Check(spec.Allowed, "capturable key accepted " key)
    pair := ValidateBindingPair(key, key)
    Check(pair.Shared, "shared key accepted " key)
    Check(ResolveKeySpec(spec.Key).Key = spec.Key, "canonical roundtrip " key)
    router := BindingInputRouter(spec, spec)
    Check(router.Role(spec.VK, spec.SC, spec.Mouse) = 3, "both roles " key)
    Check(KeyOccupancyWarning(spec) != "", "occupancy warning " key)
}
for bad in ["^a","a::ExitApp()","a`nb","Fn","scFFF","vk00","vkE7"] {
    rejected := false
    try ResolveKeySpec(bad)
    catch
        rejected := true
    Check(rejected, "hotkey syntax or uncapturable key rejected")
}
Check(ResolveKeySpec("a").Key = ResolveKeySpec("vk41").Key, "VK alias canonicalized")
for key in ["a","F1","LButton","RButton","MButton","XButton1","XButton2"] {
    spec := ResolveKeySpec(key), router := BindingInputRouter(spec, spec)
    e := router.Handle(spec.VK, spec.SC, true, false, 1000, false, spec.Mouse)
    Check(e.Consume && e.Action = 3, "first shared down")
    Loop 8 {
        e := router.Handle(spec.VK, spec.SC, true, false, 1000+A_Index, false, spec.Mouse)
        Check(e.Consume && !e.Action, "repeat suppressed")
    }
    e := router.Handle(spec.VK, spec.SC, false, true, 1100, false, spec.Mouse)
    Check(!e.Consume && router.HasHeld(), "injected release cannot clear physical latch")
    router.Pause()
    e := router.Handle(spec.VK, spec.SC, false, false, 1200, true, spec.Mouse)
    Check(e.Consume && !e.Action && !router.HasHeld(), "paired release across settings pause")
    e := router.Handle(spec.VK, spec.SC, true, false, 1300, true, spec.Mouse)
    Check(!e.Consume && !e.Action, "settings and recovery native")
    e := router.Handle(spec.VK, spec.SC, false, false, 1400, true, spec.Mouse)
    Check(!e.Consume && !router.HasHeld(), "native settings release")
}
for key in ["LWin","RWin","LAlt","RAlt","LCtrl","RCtrl","LShift","RShift"] {
    spec := ResolveKeySpec(key), router := BindingInputRouter(spec, spec)
    e := router.Handle(spec.VK, spec.SC, true, false, 1000)
    Check(!e.Consume && !e.Action, "modifier native down")
    e := router.Handle(spec.VK, spec.SC, false, false, 1100)
    Check(!e.Consume && e.Action = 3, "standalone modifier action on release")
    router.Handle(spec.VK, spec.SC, true, false, 2000)
    router.Handle(0x41, 0x1E, true, false, 2010)
    e := router.Handle(spec.VK, spec.SC, false, false, 2100)
    Check(!e.Consume && !e.Action, "modifier combination does not trigger")
    router.Handle(spec.VK, spec.SC, true, false, 3000, false, false, false, true)
    e := router.Handle(spec.VK, spec.SC, false, false, 3100)
    Check(!e.Action, "preexisting other key prevents modifier tap")
}
for key in ["WheelUp","WheelDown","WheelLeft","WheelRight"] {
    spec := ResolveKeySpec(key), router := BindingInputRouter(spec, spec)
    e := router.Handle(spec.VK, 0, true, false, 1000, false, true, true)
    Check(e.Consume && e.Action = 3 && !router.HasHeld(), "wheel first pulse")
    for tick in [1100,1250,1400] {
        e := router.Handle(spec.VK, 0, true, false, tick, false, true, true)
        Check(e.Consume && !e.Action, "wheel burst extends quiet gap")
    }
    e := router.Handle(spec.VK, 0, true, false, 1700, false, true, true)
    Check(e.Action = 3 && !router.HasHeld(), "wheel next gesture after quiet gap")
}
spec := ResolveKeySpec("Pause"), router := BindingInputRouter(spec, spec)
e := router.Handle(spec.VK, spec.SC, true, false, 1000, false, false, true)
Check(e.Action = 3 && !router.HasHeld(), "pulse keyboard has no stuck held latch")
e := router.Handle(spec.VK, spec.SC, false, false, 1100, false, false, true)
Check(e.Consume && !e.Action, "pulse release consumed once")
router := BindingInputRouter(ResolveKeySpec("F12"), ResolveKeySpec("F1"))
for vk in [0xA2,0xA4,0xA0]
    router.Handle(vk, 0, true, false, 1000)
e := router.Handle(0x7B, GetKeySC("F12"), true, false, 1100)
Check(!e.Consume && !e.Action, "fixed recovery combination remains native")
spec := ResolveKeySpec("a"), router := BindingInputRouter(spec,0)
router.Handle(spec.VK,spec.SC,true,false,1000,true)
e := router.Handle(spec.VK,spec.SC,true,false,1100,false)
Check(!e.Consume && !e.Action, "native key held across resume cannot become a trigger")
router.Handle(spec.VK,spec.SC,false,false,1200)
spec := ResolveKeySpec("LAlt"), router := BindingInputRouter(spec,0)
router.Handle(spec.VK,spec.SC,true,false,1000)
router.Pause()
router.Handle(spec.VK,spec.SC,true,false,1100)
e := router.Handle(spec.VK,spec.SC,false,false,1200)
Check(!e.Action, "held modifier across pause cannot become a fresh tap")
state := PanelActionState()
Check(state.Begin(3,1000) = "toggle", "shared begins actual query")
Check(state.Begin(3,1300) = "", "inflight reentrancy suppressed")
Check(state.Finish("toggle","panel_absent",1400) = "open", "actual absent opens")
Check(state.PollNeeded(1500), "opening guard schedules actual presence polling")
Check(state.Begin(3,1700) = "toggle", "opening can still query real panel")
Check(state.Finish("toggle","panel_absent",1800) = "", "opening delay does not send second WinH")
state.Finish("presence","panel_present",1900)
Check(!state.PollNeeded(2000) && state.Presence = "present", "actual presence synchronizes state")
Check(state.Begin(3,2200) = "toggle", "existing panel queried without parity")
Check(state.Finish("toggle","closed",2300) = "", "true close never sends WinH")
state.NativeHidden()
Check(state.Finish("toggle","panel_absent",2600) = "open", "manual close followed by actual absence opens")
for status in ["ambiguous_panel","rejected","helper_timeout_no_other_action","panel_not_ready","close_not_confirmed","no_verified_panel"] {
    state := PanelActionState()
    state.Begin(3,1000)
    Check(state.Finish("toggle",status,1100) = "", "unknown or unsafe state never opens")
}
state := PanelActionState()
Check(state.Begin(1,1000) = "open", "distinct open retains open semantics")
Check(state.Begin(1,1100) = "", "action debounce")
Check(state.Begin(2,1300) = "close", "distinct close never toggles open")
Check(state.Finish("close","panel_absent",1400) = "", "distinct close absent is no-op")
state := PanelActionState()
state.Finish("toggle","panel_absent",1000)
Check(!state.PollNeeded(6000), "opening guard expires")
f := FileOpen(ConfigPath,"w","UTF-16")
f.Write("[Mapping]`nEnabled=1`nKey=XButton1`nCloseKey=XButton2`n[Unrelated]`nValue=keep`n"), f.Close()
LoadCloseBinding()
InputState := BindingInputRouter(ResolveKeySpec(TriggerKey),CloseBindingSpec)
for pair in [["F24","F24"],["LAlt","RWin"],["LButton","RButton"],["WheelUp","WheelDown"],["XButton1","XButton2"]] {
    SaveBindingPair(pair[1],pair[2],0,FakeBind)
    Check(TriggerKey = ResolveKeySpec(pair[1]).Key && CloseKey = ResolveKeySpec(pair[2]).Key, "saved broad bindings")
    Check(IniRead(ConfigPath,"Unrelated","Value") = "keep", "unrelated config preserved")
    LoadCloseBinding()
    Check(IniRead(ConfigPath,"Mapping","Key") = TriggerKey, "persisted restart normalization")
}
before := FileRead(ConfigPath)
for failure in [FailBind,PartialPersist] {
    rejected := false
    try SaveBindingPair("F24","F24",failure = PartialPersist ? failure : 0,failure = FailBind ? failure : FakeBind)
    catch
        rejected := true
    Check(rejected && FileRead(ConfigPath) = before, "failed save rolls back config")
    Check(TriggerKey = "XButton1" && CloseKey = "XButton2", "failed save rolls back runtime pair")
}
SettingsOpen := false
CancelKeyRecording()
Check(!RecordingActive, "cancel disarms recorder")
Check(RecorderMayCapture(true,true,true,true,true,false,false), "focused keyboard recording accepted")
Check(RecorderMayCapture(true,true,true,true,true,true,true), "mouse recording only in capture area")
Check(!RecorderMayCapture(true,true,true,true,true,true,false), "save cancel defaults and record buttons remain usable")
Check(RecorderPointInside(10,20,10,20,100,80), "capture area includes upper left")
Check(RecorderPointInside(99,79,10,20,100,80), "capture area includes interior")
Check(!RecorderPointInside(100,80,10,20,100,80), "capture area excludes lower right edge")
Check(!RecorderPointInside(9,20,10,20,100,80), "adjacent settings controls stay native")
for denied in [[false,true,true,true,true,false,false],[true,false,true,true,true,false,false],[true,true,false,true,true,false,false],[true,true,true,false,true,false,false],[true,true,true,true,false,false,false]]
    Check(!RecorderMayCapture(denied*), "inactive expired or unfocused recording rejected")
RecordHeldVK := 1, RecordHeldSC := 0, RecordHeldMouse := true, RecordHeldNative := false, RecordingCancelled := true
Check(ObserveRecording(1,0,false,false,true,false) && !RecordHeldVK, "cancel retains consumed mouse release pairing")
RecordHeldVK := 0xA4, RecordHeldSC := 0x38, RecordHeldMouse := false, RecordHeldNative := true
Check(!ObserveRecording(0xA4,0x38,false,false,false,false) && !RecordHeldVK, "recorded modifier release remains native")
VoiceDispatchSink := CountTrialOpen
for enabled in [false,true] {
    SupportDiagnostics := enabled
    ActionState := PanelActionState()
    beforeOpen := TrialOpenCount
    PanelActionCompleted("toggle","panel_absent")
    StopActionTimers()
    Check(TrialOpenCount = beforeOpen + 1, "normal open remains enabled with support logging on or off")
}
SupportDiagnostics := false, VoiceDispatchSink := 0
TestLiveFrames := Map(101,{PID:1,ThreadID:2,StartFileTime:3})
PanelCandidates := Map(101,{PID:9,ThreadID:9,StartFileTime:9})
Check(RefreshPanelCandidates(RecheckTestFrame,DiscoverTestFrames) && PanelCandidates.Has(101), "WinEvent child frame survives a top-level enumeration miss")
Check(PanelCandidates[101].PID = 1, "cached frame metadata is revalidated")
TestLiveFrames.Clear()
Check(RefreshPanelCandidates(RecheckTestFrame,DiscoverTestFrames) && PanelCandidates.Count = 0, "hidden or destroyed cached frame is pruned")
TestLiveFrames := Map(202,{PID:4,ThreadID:5,StartFileTime:6}), TestDiscoveredFrames := [202]
Check(RefreshPanelCandidates(RecheckTestFrame,DiscoverTestFrames) && PanelCandidates.Has(202), "preexisting child frame discovery seeds an empty cache")
Check(RefreshPanelCandidates(RecheckTestFrame,DiscoverTestFrames) && PanelCandidates.Count = 1, "event and discovery sightings deduplicate by HWND")
TestScanFailure := true
Check(!RefreshPanelCandidates(RecheckTestFrame,DiscoverTestFrames), "incomplete native scan does not claim panel absence")
; Settings safety: Escape cannot become a recording candidate or a voice action.
Check(RecorderExitKey(0x1B,false) && !RecorderExitKey(0x1B,true), "Escape is a keyboard exit, not a mouse code")
SettingsOpen := true, RecordingActive := true, RecordHeldVK := 0
RecordDisplay := {Text:""}, SettingsWindow := 0
Check(!ObserveRecording(0x1B,1,true,false,false,false) && RecordingActive, "Escape passes natively to settings")
SettingsEscape()
Check(!RecordingActive && SettingsOpen, "first Escape stops recorder and keeps draft")
RecordingActive := true
beforeSettingsSave := FileRead(ConfigPath)
SaveSettings()
Check(FileRead(ConfigPath) = beforeSettingsSave && InStr(RecordDisplay.Text,"停止录制"), "save during recording is inline and never persists or opens modal")
CancelKeyRecording()
VoiceDispatchSink := CountTrialOpen
beforeSettingsOpen := TrialOpenCount
DispatchBoundAction(1,InputState.Generation)
Check(TrialOpenCount = beforeSettingsOpen, "settings prevents queued voice dispatch")
VoiceDispatchSink := 0
for name in ["LButton","RButton","WheelUp","WheelDown","WheelLeft","WheelRight"] {
    spec := ResolveKeySpec(name), router := BindingInputRouter(spec,spec)
    event := router.Handle(spec.VK,0,true,false,1000,true,true,spec.Pulse)
    Check(!event.Action && !event.Consume, "settings recording cannot dispatch or consume controls " name)
}
for size in [[360,320],[360,400],[420,480],[640,640],[900,720]] {
    layout := SettingsLayout(size[1],size[2])
    for name, r in layout {
        Check(r[1] >= 0 && r[2] >= 0 && r[3] > 0 && r[4] > 0 && r[1]+r[3] <= size[1] && r[2]+r[4] <= size[2], "settings rectangle fits " name)
        for other, q in layout
            if name != other
                Check(r[1]+r[3] <= q[1] || q[1]+q[3] <= r[1] || r[2]+r[4] <= q[2] || q[2]+q[4] <= r[2], "settings controls never overlap " name " " other)
    }
    if size[2] >= 400
        Check(layout["capture"][4] > 65, "capture area enlarged even in compact layout")
}
; The application's own hidden GUI supplies actual control bounds, without input injection.
ProposedTriggerSpec := ResolveKeySpec("XButton1"), ProposedCloseSpec := ResolveKeySpec("XButton1")
window := CreateSettingsWindow()
window.Show("Hide w640 h640")
ResizeSettings(window,0,640,640)
layoutEvidence := '{"source":"application own hidden GUI GetPos, not screenshot","width":640,"height":640,"dpi":' A_ScreenDPI ',"controls":{'
separator := ""
for name, control in SettingsControls {
    control.GetPos(&x,&y,&w,&h)
    expected := SettingsLayout(640,640)[name]
    Check(Abs(x-expected[1]) <= 1 && Abs(y-expected[2]) <= 1 && Abs(w-expected[3]) <= 1 && Abs(h-expected[4]) <= 1, "real control bounds match layout " name)
    layoutEvidence .= separator '"' name '":[' x ',' y ',' w ',' h ']'
    separator := ","
}
FileAppend(layoutEvidence '}}',A_ScriptDir "\settings-layout-evidence.json","UTF-8-RAW")
for size in [[360,320],[360,400],[420,480],[640,640],[900,720]] {
    window.Show("Hide w" size[1] " h" size[2])
    window.GetClientPos(,,&clientW,&clientH)
    ResizeSettings(window,0,clientW,clientH)
    nativeLayout := SettingsLayout(clientW,clientH)
    measured := '{"width":' clientW ',"height":' clientH ',"dpi":' A_ScreenDPI ',"controls":{', separator := ""
    for name, control in SettingsControls {
        control.GetPos(&x,&y,&w,&h)
        r := nativeLayout[name]
        Check(Abs(x-r[1]) <= 1 && Abs(y-r[2]) <= 1 && Abs(w-r[3]) <= 1 && Abs(h-r[4]) <= 1, "native resized control " name)
        measured .= separator '"' name '":[' x ',' y ',' w ',' h ']'
        separator := ","
    }
    FileAppend(measured '}}`n',A_ScriptDir "\settings-layout-sizes.jsonl","UTF-8-RAW")
}
RecordingActive := false, RecordHeldVK := 0
SettingsEscape()
Check(!SettingsOpen, "second Escape cancels settings with no save")
FileAppend('{"passed":' Passed ',"global_hooks_installed":false,"microphone_used":false,"WinH_sent":false,"real_UIA_invoked":false}',A_ScriptDir "\binding-unit-results.json","UTF-8-RAW")
ExitApp()
