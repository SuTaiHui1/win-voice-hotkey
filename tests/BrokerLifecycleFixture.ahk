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
global DataDir := EnvGet("WIN_VOICE_HOTKEY_DATA_DIR"), ConfigPath := DataDir "\unused.ini", TriggerKey := "XButton1"
global StopRequest := DataDir "\unused.request", CloseKey := "XButton1", Opens := 0, Tests := [], Timings := []
DirCreate(DataDir)
global TestBox := Gui("+ToolWindow -MaximizeBox -MinimizeBox","WinVoiceHotkey isolated no-input fixture")
control := TestBox.AddEdit("w320 h80","Independent empty test field")
; A hidden, independent textbox: no foreground activation or real input is used.
global FixtureFocus := control.Hwnd
class FixtureLanguageIO {
 Capture() {
  global TestBox,FixtureFocus
  return {Window:TestBox.Hwnd,Focus:FixtureFocus,Thread:DllCall("GetCurrentThreadId"),PID:DllCall("GetCurrentProcessId"),HKL:0x08040804}
 }
 Layouts() => [0x08040804]
 Now() => A_TickCount
 Request(*) => false
 Schedule(*) {
 }
}
DictationLanguageIO := FixtureLanguageIO(), VoiceDispatchSink := CountOpen, BrokerCandidateSource := EmptyCandidates
InputState := BindingInputRouter(ResolveKeySpec("XButton1"),ResolveKeySpec("XButton1"))
RuntimeState := RuntimeStateStore(DataDir,A_ScriptHwnd,1)
RuntimeState.Update(Map("MainReady",1))
OnExit(Cleanup)
InitializeCloseBrokerMode()
Check(!CloseBrokerHandle && !CloseBrokerPID && RuntimeState.Sections["State"]["Ready"] = 1,"initial standby is ready with no broker")
RequestWait("presence")
Timings.Push('"ColdReadyMs":' BrokerReadyLatencyMs)
Check(CloseLastResult = "panel_absent" && CloseBrokerReady,"real broker cold presence request succeeds")
firstPID := CloseBrokerPID
hot := BrokerClock(), RequestWait("presence")
Timings.Push('"HotEndToEndMs":' Round(BrokerClock()-hot,3))
Check(CloseBrokerPID = firstPID,"hot request reuses existing broker")
Critical("On")
SendBrokerRequest("presence","external")
Check(!StartCloseWorker("presence"),"duplicate while external request active is rejected")
Critical("Off")
WaitQuiet()
oldSeq := CloseRequestSeq, oldResult := CloseLastResult
CloseBrokerResult(((oldSeq-1)<<8)|1,CloseBrokerToken)
CloseBrokerResult((oldSeq<<8)|1,CloseBrokerToken+1)
Check(CloseLastResult = oldResult,"stale result and wrong token cannot change state")
Critical("On")
Check(SendBrokerRequest("presence","idle_probe"),"idle probe accepted")
Check(StartCloseWorker("presence") && IsObject(BrokerPending),"user request queues behind internal probe")
Critical("Off")
WaitQuiet()
Check(CloseLastResult = "panel_absent" && !ActionState.Busy,"queued request completes after probe")
Loop 30 {
 Critical("On")
 if !SendBrokerRequest("presence","idle_probe") || !StartCloseWorker("presence")
  throw Error("queued response stress request not accepted")
 Critical("Off")
 WaitQuiet()
 if CloseLastResult != "panel_absent"
  throw Error("queued response stress lost a response")
}
Check(true,"thirty immediate replies survive deferred queue dispatch")
BrokerLease.Observe("panel_present",A_TickCount)
Check(!BrokerMayIdle(),"verified panel present pins broker")
BrokerLease := BrokerIdleLease(0), BrokerLease.Observe("panel_absent",A_TickCount)
ActionState.OpeningUntil := A_TickCount+5000
Check(!BrokerMayIdle(),"opening transition pins broker")
ActionState.OpeningUntil := 0, ChineseLanguageGate.Pending := {Test:true}
Check(!BrokerMayIdle(),"language preparation pins broker")
ChineseLanguageGate.Pending := 0
BrokerNativePanelChanged()
Check(!BrokerMayIdle(),"native panel event invalidates absence")
BrokerLease := BrokerIdleLease(120000), BrokerLease.Touch(A_TickCount)
WriteCloseStatus()
FileAppend('{"mainPID":' DllCall("GetCurrentProcessId") ',"brokerPID":' CloseBrokerPID '}',DataDir "\active-ready.json","UTF-8-RAW")
WaitFile("active-sample-done",60000)
BrokerLease := BrokerIdleLease(10000), BrokerLease.Touch(A_TickCount)
reclaim := BrokerClock()
WaitUntilIdle(18000)
Timings.Push('"ReclaimAfterSampleMs":' Round(BrokerClock()-reclaim,3))
Check(!ProcessExist(firstPID) && RuntimeState.Sections["State"]["Ready"] = 1,"verified absence reclaims cooperatively and main stays ready")
FileAppend('{"mainPID":' DllCall("GetCurrentProcessId") ',"brokerPID":0}',DataDir "\reclaimed-ready.json","UTF-8-RAW")
WaitFile("idle-sample-done",60000)
start := BrokerClock(), RequestWait("presence")
Timings.Push('"ReclaimedColdReadyMs":' BrokerReadyLatencyMs ',"ReclaimedRequestMs":' Round(BrokerClock()-start,3))
Check(CloseBrokerPID != firstPID,"request after reclaim restarts helper")
; A new request during cooperative stopping must wait, then launch exactly one replacement.
BrokerLease := BrokerIdleLease(0), BrokerLease.Observe("panel_absent",A_TickCount)
closingPID := CloseBrokerPID
Check(BeginIdleBrokerStop(),"idle exit request accepted")
Check(StartCloseWorker("presence") && IsObject(BrokerPending),"request while stopping is queued")
WaitQuiet()
Check(CloseBrokerReady && CloseBrokerPID != closingPID && CloseLastResult = "panel_absent","queued request survives stopping boundary")
; Kill only this isolated fixture's helper, never the daily program or Windows services.
crashedPID := CloseBrokerPID
DllCall("TerminateProcess","Ptr",CloseBrokerHandle,"UInt",199)
endTick := A_TickCount+3000
while CloseBrokerHandle && A_TickCount < endTick
 Sleep(10)
Check(!CloseBrokerHandle && BrokerPhase = "failed" && BrokerLastError = "helper_exited","crash is a truthful recoverable failure")
Sleep(500)
Check(!CloseBrokerHandle,"crash does not cause background respawn")
RequestWait("presence")
Check(CloseBrokerReady && CloseBrokerPID != crashedPID,"next request recovers crashed helper")
StopCloseWorker()
; Rapid second key cancels an unsent cold toggle; no Win+H is sent.
ActionState := PanelActionState(), PendingVoiceTarget := DictationLanguageIO.Capture()
ActionState.Busy := true
Check(StartCloseWorker("toggle"),"cold toggle queued")
DispatchBoundAction(3,InputState.Generation,PendingVoiceTarget)
WaitReady()
Check(!BrokerPending && Opens = 0 && CloseLastResult = "cancelled","repeated key cancels cold queued toggle")
StopCloseWorker()
; Target changes before cold readiness cancel rather than using a new editor.
ActionState := PanelActionState(), PendingVoiceTarget := DictationLanguageIO.Capture()
ActionState.Busy := true
StartCloseWorker("toggle")
FixtureFocus += 1
WaitReady()
Check(!BrokerPending && !ActionState.Busy && Opens = 0,"focus change cancels queued cold open")
FixtureFocus -= 1
StopCloseWorker()
ActionState := PanelActionState(), PendingVoiceTarget := DictationLanguageIO.Capture()
ActionState.Busy := true
StartCloseWorker("toggle")
InputState.Generation += 1
WaitReady()
Check(!BrokerPending && !ActionState.Busy && Opens = 0,"binding generation change cancels cold request")
finalPID := CloseBrokerPID
StopCloseWorker()
Check(!ProcessExist(finalPID) && !CloseBrokerHandle,"program cleanup removes its own broker")
FileAppend('{"passed":' Passed ',"tests":[' JoinStrings(Tests) '],"timings":{' JoinStrings(Timings) '},"microphone_used":false,"WinH_sent":false,"real_broker":true,"real_panel_open_close":false}',DataDir "\lifecycle-results.json","UTF-8-RAW")
ExitApp()
JoinStrings(values) {
 s := ""
 for value in values
  s .= (s = "" ? "" : ",") value
 return s
}
Check(ok,label) {
 global Passed,Tests
 if !ok
  throw Error(label)
 Passed += 1, Tests.Push('"' label '"')
}
CountOpen(*) {
 global Opens
 Opens += 1
}
EmptyCandidates() {
 global PanelCandidates,PanelCandidateOverflow
 PanelCandidates.Clear(), PanelCandidateOverflow := false
 return true
}
WriteMappingStatus(*) {
}
WaitQuiet() {
 global CloseBusy,BrokerPending,CloseBrokerReady,BrokerPhase
 deadline := A_TickCount+8000
 while (CloseBusy || IsObject(BrokerPending) || BrokerPhase = "starting" || BrokerPhase = "stopping") && A_TickCount < deadline
  Sleep(5)
 if !CloseBrokerReady || CloseBusy || IsObject(BrokerPending)
  throw Error("broker request did not complete: " BrokerPhase)
}
WaitReady() {
 global CloseBrokerReady,BrokerPhase
 deadline := A_TickCount+6000
 while !CloseBrokerReady && A_TickCount < deadline
  Sleep(5)
 Sleep(20)
 if !CloseBrokerReady
  throw Error("readiness timeout: " BrokerPhase)
}
RequestWait(mode) {
 global ActionState
 ActionState.Busy := true
 if !StartCloseWorker(mode)
  throw Error("request not accepted")
 WaitQuiet()
}
WaitUntilIdle(timeout) {
 global CloseBrokerHandle,BrokerPhase
 deadline := A_TickCount+timeout
 while CloseBrokerHandle && A_TickCount < deadline
  Sleep(20)
 if CloseBrokerHandle || BrokerPhase != "idle"
  throw Error("idle reclaim did not complete: " BrokerPhase)
}
WaitFile(name,timeout) {
 global DataDir
 deadline := A_TickCount+timeout
 while !FileExist(DataDir "\" name) && A_TickCount < deadline
  Sleep(30)
 if !FileExist(DataDir "\" name)
  throw Error("measurement handshake timeout: " name)
}
Cleanup(*) {
 StopCloseWorker()
}
Failed(problem,*) {
 global DataDir
 try FileAppend(problem.Message "`n" problem.Stack,DataDir "\fixture-error.txt","UTF-8-RAW")
 ExitApp(1)
}