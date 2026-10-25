#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError(Failed)
#Include RuntimeState.ahk
#Include KeyCatalog.ahk
#Include SupportDiagnostics.ahk
#Include InputRouter.ahk
#Include KeyboardObserver.ahk
#Include GlobalRuntime.ahk
#Include KeySettings.ahk
#Include CloseBrokerRuntime.ahk
global Passed := 0, SettingsOpen := false, SettingsWindow := 0, SmokeTest := true
global RecoveryPaused := false, DataDir := A_ScriptDir, ConfigPath := A_ScriptDir "\language-test.ini", TriggerKey := "XButton1"
global TrialOpenCount := 0, LastLanguageNotice := "", StopRequest := A_ScriptDir "\unused-stop.request", BrokerTrials := []
InputState := BindingInputRouter(ResolveKeySpec("XButton1"),ResolveKeySpec("XButton1"))
class LanguageStatusFixture {
 __New() {
  this.LastResult := ""
 }
 Update(values) {
  this.LastResult := values["LanguageResult"]
 }
}
class FakeLanguageIO {
 __New(hkl := 0x04094C09) {
  this.Context := {Window:101,Focus:102,Thread:103,PID:104,HKL:hkl}
  this.Available := [0x08040804,0x04094C09], this.Clock := 0, this.Requests := 0, this.Allow := true, this.Scheduled := false, this.Reads := 0, this.FlipAt := 0
 }
 Capture() {
  this.Reads += 1
  if this.FlipAt && this.Reads >= this.FlipAt && this.Context
   this.Context.Window := 999
  return this.Context ? this.Context.Clone() : 0
 }
 Layouts() => this.Available
 Now() => this.Clock
 Request(target, layout) {
  this.Requests += 1
  return this.Allow
 }
 Schedule(enabled) {
  this.Scheduled := enabled
 }
}
Check(ok,label) {
 global Passed
 if !ok
  throw Error(label)
 Passed += 1
}
Failed(problem,*) {
 FileAppend(problem.Message "`n" problem.Stack,"**")
 ExitApp(1)
}
WriteMappingStatus(*) {
}
CountTrialOpen(*) {
 global TrialOpenCount
 TrialOpenCount += 1
}
RecordLanguageNotice(result) {
 global LastLanguageNotice
 LastLanguageNotice := result
}
RecordBroker(mode) {
 global BrokerTrials
 BrokerTrials.Push(mode)
}
ResetLanguage(hkl := 0x04094C09) {
 global DictationLanguageIO,VoiceDispatchSink,DictationLanguageNotificationSink,TrialOpenCount,LastLanguageNotice,RuntimeState
 global InputState,SettingsOpen,RecoveryPaused,ActionState,BrokerRequestSink,BrokerTrials,PendingVoiceTarget
 StopChineseDictation()
 RuntimeState := LanguageStatusFixture()
 DictationLanguageIO := FakeLanguageIO(hkl), VoiceDispatchSink := CountTrialOpen, DictationLanguageNotificationSink := RecordLanguageNotice
 TrialOpenCount := 0, LastLanguageNotice := "", SettingsOpen := false, RecoveryPaused := false, ActionState := PanelActionState()
 InputState := BindingInputRouter(ResolveKeySpec("XButton1"),ResolveKeySpec("XButton1"))
 BrokerRequestSink := RecordBroker, BrokerTrials := [], PendingVoiceTarget := 0
}
AckChinese() {
 global DictationLanguageIO
 DictationLanguageIO.Context.HKL := 0x08040804, DictationLanguageIO.Clock += 10
 CheckChineseDictation()
 DictationLanguageIO.Clock += 60
 CheckChineseDictation()
}
ResetLanguage()
DispatchVoiceRequest()
Check(TrialOpenCount = 0,"English target must not dispatch WinH before Chinese confirmation")
Check(DictationLanguageIO.Requests = 1 && DictationLanguageIO.Scheduled,"specific Chinese request scheduled once")
DictationLanguageIO.Clock := 300
CheckChineseDictation()
Check(TrialOpenCount = 0,"unacknowledged request never dispatches")
AckChinese()
Check(TrialOpenCount = 1 && !ChineseLanguageGate.Pending,"confirmed stable Chinese dispatches exactly once")
Check(!DictationLanguageIO.Scheduled,"successful request releases preparation timer")
CheckChineseDictation()
Check(TrialOpenCount = 1,"duplicate completion cannot send a second shortcut")
ResetLanguage(0x08040804)
DispatchVoiceRequest()
Check(TrialOpenCount = 1 && DictationLanguageIO.Requests = 0,"already Chinese does not switch profiles")
ResetLanguage()
DictationLanguageIO.Available := [0x04094C09,0x04040404]
DispatchVoiceRequest()
Check(TrialOpenCount = 0 && DictationLanguageIO.Requests = 0 && RuntimeState.LastResult = "missing_chinese","missing simplified Chinese clearly rejects without opening")
ResetLanguage()
DictationLanguageIO.Allow := false
DispatchVoiceRequest()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "switch_request_failed" && !ChineseLanguageGate.Pending,"rejected request never claims success")
ResetLanguage()
DispatchVoiceRequest()
DictationLanguageIO.Clock := 1001
CheckChineseDictation()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "switch_timeout" && !ChineseLanguageGate.Pending,"timeout rejects stale language")
for field in ["Window","Focus","Thread","PID"] {
 ResetLanguage()
 DispatchVoiceRequest()
 DictationLanguageIO.Context.%field% += 1
 CheckChineseDictation()
 Check(TrialOpenCount = 0 && RuntimeState.LastResult = "focus_changed","changed target identity cancels " field)
 Check(DictationLanguageIO.Requests = 1,"cancel does not send restore or chase new focus " field)
}
ResetLanguage()
DispatchVoiceRequest()
DictationLanguageIO.Context.HKL := 0x04090409
CheckChineseDictation()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "user_language_changed","different user-selected language cancels without retry")
ResetLanguage()
DispatchVoiceRequest()
DictationLanguageIO.Context.HKL := 0x08040804, DictationLanguageIO.Clock := 20
CheckChineseDictation()
Check(TrialOpenCount = 0,"first Chinese observation alone is not sufficient")
DictationLanguageIO.Context.HKL := 0x04094C09, DictationLanguageIO.Clock := 35
CheckChineseDictation()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "user_language_changed","user switches back before stable confirmation")
for condition in ["generation","settings","paused","modifier"] {
 ResetLanguage()
 DispatchVoiceRequest()
 switch condition {
  case "generation": InputState.Pause()
  case "settings": SettingsOpen := true
  case "paused": RecoveryPaused := true
  case "modifier": InputState.Modifiers[0x5B] := true
 }
 CheckChineseDictation()
 Check(TrialOpenCount = 0 && !ChineseLanguageGate.Pending,"preparation invalidation cancels " condition)
}
ResetLanguage()
old := DictationLanguageIO.Capture()
DictationLanguageIO.Context.HKL := 0x08040804
DispatchVoiceRequest(old)
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "user_language_changed","language changed while broker query was pending")
ResetLanguage()
old := DictationLanguageIO.Capture()
DictationLanguageIO.Context.Focus += 1
DispatchVoiceRequest(old)
Check(TrialOpenCount = 0 && DictationLanguageIO.Requests = 0,"changed focus before preparation receives no language request")
ResetLanguage()
DictationLanguageIO.Context := 0
DispatchVoiceRequest()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "no_target","missing focus never opens")
ResetLanguage(0x08040804)
DictationLanguageIO.FlipAt := 2
DispatchVoiceRequest()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "focus_changed","Chinese target is rechecked immediately before shortcut")
ResetLanguage()
DispatchVoiceRequest()
DictationLanguageIO.Context.HKL := 0x08040804, DictationLanguageIO.Clock := 10
CheckChineseDictation()
DictationLanguageIO.FlipAt := DictationLanguageIO.Reads+2, DictationLanguageIO.Clock := 80
CheckChineseDictation()
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "focus_changed","last-moment focus change cancels after stable samples")
ResetLanguage()
DispatchVoiceRequest()
DispatchBoundAction(1,InputState.Generation)
Check(DictationLanguageIO.Requests = 1 && TrialOpenCount = 0,"repeat open while preparing is ignored")
DispatchBoundAction(3,InputState.Generation)
Check(!ChineseLanguageGate.Pending && TrialOpenCount = 0,"second shared-key action cancels a pending open")
Check(DictationLanguageIO.Requests = 1,"cancellation does not restore or force another layout")
DispatchVoiceRequest()
AckChinese()
Check(TrialOpenCount = 1,"fresh request after cancellation may open")
ResetLanguage()
DispatchVoiceRequest()
DispatchBoundAction(2,InputState.Generation)
Check(!ChineseLanguageGate.Pending && TrialOpenCount = 0 && BrokerTrials.Length = 0,"close key cancels pending open without opening or closing something else")
ResetLanguage()
DispatchBoundAction(2,InputState.Generation)
Check(BrokerTrials.Length = 1 && BrokerTrials[1] = "close" && DictationLanguageIO.Requests = 0,"distinct close retains original broker route and language")
PanelActionCompleted("close","closed")
Check(TrialOpenCount = 0 && DictationLanguageIO.Requests = 0,"successful close never switches input language")
ResetLanguage()
DispatchBoundAction(3,InputState.Generation)
PanelActionCompleted("toggle","closed")
Check(TrialOpenCount = 0 && DictationLanguageIO.Requests = 0,"shared key closing a present panel does not switch language")
ResetLanguage()
DispatchBoundAction(3,InputState.Generation)
PanelActionCompleted("toggle","panel_absent")
Check(DictationLanguageIO.Requests = 1 && TrialOpenCount = 0,"absent panel begins language preparation through actual broker result")
AckChinese()
Check(TrialOpenCount = 1,"shared-key absent result opens only after Chinese acknowledgment")
ResetLanguage()
DispatchBoundAction(3,InputState.Generation)
DictationLanguageIO.Context.Window += 1
PanelActionCompleted("toggle","panel_absent")
Check(TrialOpenCount = 0 && DictationLanguageIO.Requests = 0 && RuntimeState.LastResult = "focus_changed","window switch during panel query cannot dictate into new window")
ResetLanguage()
DispatchBoundAction(3,InputState.Generation,0)
PanelActionCompleted("toggle","panel_absent")
Check(TrialOpenCount = 0 && RuntimeState.LastResult = "no_target","missing original target cannot be replaced with a new foreground window")
ResetLanguage()
DispatchVoiceRequest()
StopActionTimers()
Check(!ChineseLanguageGate.Pending && !DictationLanguageIO.Scheduled && TrialOpenCount = 0,"shutdown or timer cleanup cannot leave a delayed open")
Check(ChooseChineseLayout([0x04094C09,0x04040404,0x08040804]) = 0x08040804,"selects explicit zh-CN rather than cycling or choosing traditional Chinese")
Check(!IsSimplifiedChineseLayout(0x04040404) && !IsSimplifiedChineseLayout(0x04094C09),"traditional Chinese and unsupported English are not accepted as zh-CN")
Check(ChooseChineseLayout([0x08040804],0xE0200804) = 0xE0200804,"preserves an already active simplified Chinese profile")
ResetLanguage(0x08040804)
for quiet in ["ready","switching","not_requested","cancelled"] {
 LastLanguageNotice := ""
 SetDictationLanguageResult(quiet,true)
 Check(LastLanguageNotice = "" && RuntimeState.LastResult = quiet,"success/progress/cancel stays silent with truthful state " quiet)
}
for failure in ["missing_chinese","no_target","focus_changed","user_language_changed","switch_request_failed","switch_timeout"] {
 LastLanguageNotice := ""
 SetDictationLanguageResult(failure,true)
 Check(LastLanguageNotice = "" && RuntimeState.LastResult = failure,"failure stays silent while original failure state remains " failure)
}
LastLanguageNotice := ""
SetDictationLanguageResult("switch_timeout",false)
Check(LastLanguageNotice = "","caller notification opt-out remains effective")
ResetLanguage(0x08040804)
DispatchVoiceRequest()
Check(TrialOpenCount = 1 && LastLanguageNotice = "","normal successful Chinese wake remains silent")
ResetLanguage()
DispatchVoiceRequest()
Check(LastLanguageNotice = "","normal switch preparation remains silent")
AckChinese()
Check(TrialOpenCount = 1 && LastLanguageNotice = "","confirmed switch success remains silent")
StopActionTimers()
FileAppend('{"passed":' Passed ',"global_hooks_installed":false,"voice_sent":false,"microphone_used":false,"real_UIA_invoked":false}',A_ScriptDir "\language-unit-results.json","UTF-8-RAW")
ExitApp()