#Include PanelWindowTracker.ahk
#Include BrokerIdlePolicy.ahk
global CloseActionSink := 0, CloseAcceptanceLog := "", BrokerRequestSink := 0, BrokerCandidateSource := 0
global PendingBrokerGeneration := 0, CloseLastResult := "not_requested", CloseLastRequested := "", CloseLatencyMs := 0
global CloseBrokerHandle := 0, CloseBrokerPID := 0, CloseBrokerHWND := 0, CloseBrokerToken := 0, CloseBrokerReady := false
global CloseBrokerReadyPath := "", CloseBrokerStarted := 0, CloseRequestSeq := 0, CloseBusy := false, CloseStartedTick := 0
global BrokerMode := "resident", BrokerLifecycleReady := false, BrokerPhase := "idle", BrokerPending := 0
global BrokerLease := BrokerIdleLease(), BrokerOrigin := "", BrokerNativeEpoch := 0, BrokerRequestEpoch := 0
global BrokerLastProbe := 0, BrokerStopStarted := 0, BrokerStartQPC := 0, BrokerRequestQPC := 0
global BrokerReadyLatencyMs := 0, BrokerRequestLatencyMs := 0, BrokerLastError := "", BrokerLastProbeResult := "unknown"
BrokerClock() {
 static frequency := 0
 if !frequency
  DllCall("QueryPerformanceFrequency","Int64*",&frequency)
 counter := 0
 DllCall("QueryPerformanceCounter","Int64*",&counter)
 return counter*1000.0/frequency
}
InitializeCloseBrokerMode() {
 global BrokerMode,BrokerLifecycleReady,BrokerPhase,BrokerLease
 BrokerMode := "on_demand", BrokerLifecycleReady := true, BrokerPhase := "idle"
 BrokerLease.Touch(A_TickCount)
 WriteCloseStatus()
}
MouseCloseVoice(vk,*) {
 global SettingsOpen,CloseBindingSpec,CloseActionSink
 if SettingsOpen || !IsObject(CloseBindingSpec) || CloseBindingSpec.VK != vk
  return
 if IsObject(CloseActionSink)
  CloseActionSink.Call()
 else
  StartCloseWorker()
}
StartCloseBroker() {
 global DataDir,CloseBrokerHandle,CloseBrokerPID,CloseBrokerHWND,CloseBrokerToken,CloseBrokerReady,CloseBrokerReadyPath,CloseBrokerStarted
 global BrokerPhase,BrokerPending,BrokerStartQPC,BrokerLastError,CloseLastResult,RuntimeState
 if CloseBrokerHandle
  return BrokerPhase != "failed"
 if IsObject(BrokerPending) {
  if BrokerPending.Starts >= 1
   return false
  BrokerPending.Starts += 1
 }
 guid := Buffer(16), text := Buffer(80)
 if DllCall("ole32\CoCreateGuid","Ptr",guid,"Int") != 0
  return BrokerFailed("helper_start_failed")
 DllCall("ole32\StringFromGUID2","Ptr",guid,"Ptr",text,"Int",40)
 id := Trim(StrGet(text),"{}")
 CloseBrokerToken := Random(1,2147483647), CloseBrokerReady := false, CloseBrokerHWND := 0
 CloseBrokerReadyPath := DataDir "\close-broker-" id ".ready.json"
 DllCall("SetPropW","Ptr",A_ScriptHwnd,"WStr","WinVoiceHotkeyBrokerOwner","Ptr",CloseBrokerToken)
 OnMessage(0x805A,CloseBrokerResult)
 BrokerPhase := "starting", BrokerStartQPC := BrokerClock(), CloseBrokerStarted := A_TickCount
 try {
  Run('"' A_ScriptDir '\VoicePanelBroker.exe" --broker ' id " " DllCall("GetCurrentProcessId","UInt") " " A_ScriptHwnd " " CloseBrokerToken,A_ScriptDir,"Hide",&CloseBrokerPID)
  CloseBrokerHandle := DllCall("OpenProcess","UInt",0x101001,"Int",false,"UInt",CloseBrokerPID,"Ptr")
  if !CloseBrokerHandle
   return BrokerFailed("helper_start_failed")
 } catch
  return BrokerFailed("helper_start_failed")
 SetTimer(PollCloseBrokerReady,25), SetTimer(WatchCloseWorker,200)
 WriteCloseStatus()
 if IsObject(RuntimeState)
  RuntimeState.Event("broker_starting")
 return true
}
PollCloseBrokerReady(*) {
 global CloseBrokerHandle,CloseBrokerReadyPath,CloseBrokerHWND,CloseBrokerPID,CloseBrokerReady,CloseBrokerToken,CloseBrokerStarted
 global BrokerPhase,BrokerReadyLatencyMs,BrokerStartQPC,BrokerLease,BrokerLastProbe,RuntimeState
 if !CloseBrokerHandle {
  SetTimer(PollCloseBrokerReady,0)
  return
 }
 if FileExist(CloseBrokerReadyPath) {
  try {
   json := FileRead(CloseBrokerReadyPath,"UTF-8")
   if !RegExMatch(json,'"HWND":(\d+)',&h) || !RegExMatch(json,'"Token":(\d+)',&t)
    return
   owner := 0
   DllCall("GetWindowThreadProcessId","Ptr",h[1],"UInt*",&owner)
   if owner != CloseBrokerPID || t[1] != CloseBrokerToken
    return
  } catch
   return
  CloseBrokerHWND := h[1]+0, CloseBrokerReady := true, BrokerPhase := "ready"
  BrokerReadyLatencyMs := Round(BrokerClock()-BrokerStartQPC,3)
  BrokerLease.Touch(A_TickCount), BrokerLastProbe := A_TickCount
  try FileDelete(CloseBrokerReadyPath)
  SetTimer(PollCloseBrokerReady,0)
  WriteCloseStatus()
  if IsObject(RuntimeState)
   RuntimeState.Event("broker_ready")
  FlushBrokerPending()
 }
 if !CloseBrokerReady && A_TickCount-CloseBrokerStarted > 4000
  BrokerFailed("helper_start_timeout")
}
QueueBrokerRequest(mode) {
 global BrokerPending,InputState,PendingVoiceTarget,BrokerLease
 if IsObject(BrokerPending)
  return false
 BrokerPending := {Mode:mode,Generation:IsObject(InputState) ? InputState.Generation : 0,Target:PendingVoiceTarget,Starts:0}
 BrokerLease.Touch(A_TickCount)
 return true
}
CancelQueuedBrokerOpen() {
 global BrokerPending,ActionState,PendingVoiceTarget,CloseLastResult
 if !IsObject(BrokerPending) || BrokerPending.Mode != "toggle"
  return false
 BrokerPending := 0, PendingVoiceTarget := 0, CloseLastResult := "cancelled"
 ActionState.OpeningUntil := 0, ActionState.Cancel()
 WriteCloseStatus()
 return true
}
FlushBrokerPending() {
 global BrokerPending,InputState,SettingsOpen,RecoveryPaused,ActionState,PendingVoiceTarget,DictationLanguageIO
 if !IsObject(BrokerPending)
  return
 p := BrokerPending, BrokerPending := 0
 valid := IsObject(InputState) && p.Generation = InputState.Generation && !SettingsOpen && !RecoveryPaused
 if valid && p.Mode = "toggle" && IsObject(p.Target)
  valid := SameDictationTarget(p.Target,DictationLanguageIO.Capture())
 if !valid {
  PendingVoiceTarget := 0, ActionState.OpeningUntil := 0, ActionState.Cancel()
  return
 }
 PendingVoiceTarget := p.Target
 if !SendBrokerRequest(p.Mode,"external")
  ActionState.Cancel()
}
StartCloseWorker(mode := "close") {
 global BrokerRequestSink,CloseBusy,BrokerOrigin,CloseBrokerReady,CloseBrokerHandle,BrokerPhase,ActionState
 if mode != "close" && mode != "toggle" && mode != "presence"
  return false
 if IsObject(BrokerRequestSink) {
  BrokerRequestSink.Call(mode)
  return true
 }
 if CloseBusy {
  if BrokerOrigin = "idle_probe"
   return QueueBrokerRequest(mode)
  return false
 }
 if !CloseBrokerReady {
  if !QueueBrokerRequest(mode)
   return false
  if CloseBrokerHandle {
   if BrokerPhase = "starting" || BrokerPhase = "stopping"
    return true
   return BrokerFailed("helper_not_ready")
  }
  return StartCloseBroker()
 }
 return SendBrokerRequest(mode,"external")
}
SendBrokerRequest(mode,origin) {
 global CloseBrokerReady,CloseBrokerHWND,CloseBrokerToken,CloseRequestSeq,CloseBusy,CloseStartedTick,CloseLastRequested,CloseLastResult
 global PendingBrokerAction,PendingBrokerGeneration,InputState,PanelCandidateOverflow,BrokerCandidateSource,BrokerOrigin,BrokerRequestEpoch,BrokerNativeEpoch
 global BrokerLease,BrokerRequestQPC,BrokerLastProbe,BrokerPhase
 if !CloseBrokerReady || CloseBusy
  return false
 okay := IsObject(BrokerCandidateSource) ? BrokerCandidateSource.Call() : RefreshPanelCandidates()
 if !okay || PanelCandidateOverflow {
  if origin = "external"
   CloseLastResult := "candidate_scan_incomplete"
  BrokerLease.Invalidate(), WriteCloseStatus()
  return false
 }
 CloseRequestSeq += 1
 json := '{"Seq":' CloseRequestSeq ',"Action":"' mode '","Candidates":' PanelCandidateJSON() '}'
 bytes := Buffer(StrPut(json,"UTF-8"),0), StrPut(json,bytes,"UTF-8")
 packet := Buffer(A_PtrSize*3,0)
 NumPut("Ptr",CloseBrokerToken,packet,0), NumPut("UInt",bytes.Size,packet,A_PtrSize), NumPut("Ptr",bytes.Ptr,packet,A_PtrSize*2)
 CloseBusy := true, CloseStartedTick := A_TickCount, BrokerRequestQPC := BrokerClock(), BrokerOrigin := origin, BrokerRequestEpoch := BrokerNativeEpoch
 PendingBrokerAction := mode, PendingBrokerGeneration := IsObject(InputState) ? InputState.Generation : 0
 BrokerPhase := "busy", BrokerLastProbe := A_TickCount
 if origin = "external" {
  BrokerLease.Touch(A_TickCount)
  CloseLastRequested := A_NowUTC, CloseLastResult := "pending"
 }
 result := 0
 okay := DllCall("SendMessageTimeoutW","Ptr",CloseBrokerHWND,"UInt",0x4A,"Ptr",A_ScriptHwnd,"Ptr",packet,"UInt",2,"UInt",200,"Ptr*",&result,"Ptr")
 if !okay || result != 1 {
  CloseBusy := false, BrokerPhase := "ready"
  if origin = "external"
   CloseLastResult := result = 2 ? "helper_busy" : "helper_not_ready"
  BrokerLease.Invalidate(), WriteCloseStatus()
  return false
 }
 WriteCloseStatus()
 return true
}
CloseBrokerResult(packed,token,*) {
 global CloseBrokerToken,CloseRequestSeq,CloseBusy,CloseLastResult,CloseStartedTick,CloseLatencyMs,CloseAcceptanceLog,DataDir
 global PendingBrokerAction,PendingBrokerGeneration,InputState,ActionState,BrokerOrigin,BrokerPhase,BrokerLease,BrokerRequestLatencyMs,BrokerRequestQPC
 global BrokerLastProbeResult,BrokerRequestEpoch,BrokerNativeEpoch,BrokerPending
 if token != CloseBrokerToken || (packed >> 8) != CloseRequestSeq || !CloseBusy
  return
 codes := Map(1,"closed",2,"no_verified_panel",3,"ambiguous_panel",4,"close_not_confirmed",5,"rejected",6,"helper_timeout_no_other_action",7,"panel_present",8,"panel_absent",9,"panel_not_ready")
 status := codes.Has(packed & 255) ? codes[packed & 255] : "helper_result_unknown"
 origin := BrokerOrigin, mode := PendingBrokerAction
 CloseBusy := false, BrokerPhase := "ready", BrokerRequestLatencyMs := Round(BrokerClock()-BrokerRequestQPC,3)
 if BrokerRequestEpoch = BrokerNativeEpoch
  BrokerLease.Observe(status,A_TickCount)
 else
  BrokerLease.Invalidate()
 if origin = "external" {
  CloseLastResult := status, CloseLatencyMs := A_TickCount-CloseStartedTick
  if CloseAcceptanceLog != "" {
   try {
    json := FileRead(DataDir "\close-last-result.json","UTF-8")
    if RegExMatch(json,'"Seq":' CloseRequestSeq '(,|})')
     FileAppend(json "`n",CloseAcceptanceLog,"UTF-8-RAW")
   }
  }
  WriteCloseStatus()
  if IsObject(InputState) && InputState.Generation = PendingBrokerGeneration
   PanelActionCompleted(mode,status)
  else
   ActionState.Cancel()
 } else {
  BrokerLastProbeResult := status
  WriteCloseStatus()
 }
 if IsObject(BrokerPending)
  ; Return from this OnMessage handler before a new fast reply can arrive.
  SetTimer(FlushBrokerPending,-1)
 else if origin = "idle_probe" && status = "panel_absent" && BrokerMayIdle()
  BeginIdleBrokerStop()
}
BrokerMayIdle() {
 global BrokerLease,CloseBusy,BrokerPending,ActionState,ChineseLanguageGate,CloseBrokerReady
 return CloseBrokerReady && BrokerLease.CanReclaim(A_TickCount,CloseBusy || ActionState.Busy,IsObject(BrokerPending),ActionState.PollNeeded(A_TickCount),IsObject(ChineseLanguageGate.Pending))
}
BrokerVoiceOpenDispatched() {
 global CloseBrokerHandle,BrokerLease
 if CloseBrokerHandle {
  BrokerLease.Touch(A_TickCount), BrokerLease.Invalidate()
  WriteCloseStatus()
 }
}
BrokerNativePanelChanged() {
 global BrokerNativeEpoch,BrokerLease
 BrokerNativeEpoch += 1, BrokerLease.Invalidate()
}
BeginIdleBrokerStop() {
 global CloseBrokerHWND,CloseBrokerToken,CloseBrokerReady,BrokerPhase,BrokerStopStarted,RuntimeState
 if !BrokerMayIdle()
  return false
 if !DllCall("PostMessageW","Ptr",CloseBrokerHWND,"UInt",0x9001,"Ptr",A_ScriptHwnd,"Ptr",CloseBrokerToken)
  return BrokerFailed("idle_stop_request_failed")
 CloseBrokerReady := false, BrokerPhase := "stopping", BrokerStopStarted := A_TickCount
 WriteCloseStatus()
 if IsObject(RuntimeState)
  RuntimeState.Event("broker_idle_exit_requested")
 return true
}
WatchCloseWorker(*) {
 global CloseBrokerHandle,CloseBusy,CloseStartedTick,CloseBrokerReady,BrokerPhase,BrokerPending,BrokerLastProbe,BrokerStopStarted
 global BrokerLease,ActionState,ChineseLanguageGate,RuntimeState,CloseLastResult,BrokerLastError
 if !CloseBrokerHandle {
  SetTimer(WatchCloseWorker,0)
  return
 }
 if DllCall("WaitForSingleObject","Ptr",CloseBrokerHandle,"UInt",0) = 0 {
  normalIdle := BrokerPhase = "stopping", startup := BrokerPhase = "starting"
  wasBusy := CloseBusy
  ReleaseBrokerHandles()
  CloseBusy := false, BrokerPhase := normalIdle ? "idle" : "failed"
  if !normalIdle {
   BrokerLastError := "helper_exited"
   if wasBusy
    CloseLastResult := "helper_exited", ActionState.Cancel()
  }
  if IsObject(RuntimeState)
   RuntimeState.Event(normalIdle ? "broker_idle" : "broker_exited")
  WriteCloseStatus()
  if IsObject(BrokerPending) {
   if !startup && BrokerPending.Starts < 1
    StartCloseBroker()
   else
    BrokerFailed("helper_exited_before_ready")
  }
  return
 }
 if BrokerPhase = "stopping" && A_TickCount-BrokerStopStarted > 2000 {
  ; No force-kill for idle reclamation and no second helper while the old process is alive.
  BrokerLastError := "idle_exit_timeout", BrokerPhase := "failed", BrokerPending := 0
  ActionState.Cancel(), WriteCloseStatus()
  return
 }
 if CloseBusy && A_TickCount-CloseStartedTick > 2500 {
  BrokerFailed("helper_request_timeout")
  return
 }
 if !CloseBrokerReady || CloseBusy || IsObject(BrokerPending) || ActionState.PollNeeded(A_TickCount) || IsObject(ChineseLanguageGate.Pending)
  return
 if A_TickCount-BrokerLastProbe >= 2000
  SendBrokerRequest("presence","idle_probe")
}
BrokerFailed(reason) {
 global BrokerPending,CloseBusy,CloseLastResult,BrokerLastError,BrokerPhase,ActionState,RuntimeState
 BrokerPending := 0, CloseBusy := false, CloseLastResult := reason, BrokerLastError := reason
 StopCloseWorker()
 BrokerPhase := "failed", ActionState.OpeningUntil := 0, ActionState.Cancel()
 WriteCloseStatus()
 if IsObject(RuntimeState)
  RuntimeState.Event("broker_error",reason)
 return false
}
ReleaseBrokerHandles() {
 global CloseBrokerHandle,CloseBrokerPID,CloseBrokerHWND,CloseBrokerReady,CloseBrokerToken,CloseBrokerReadyPath
 SetTimer(PollCloseBrokerReady,0), SetTimer(WatchCloseWorker,0)
 if CloseBrokerHandle
  DllCall("CloseHandle","Ptr",CloseBrokerHandle)
 CloseBrokerHandle := 0, CloseBrokerPID := 0, CloseBrokerHWND := 0, CloseBrokerReady := false, CloseBrokerToken := 0
 DllCall("RemovePropW","Ptr",A_ScriptHwnd,"WStr","WinVoiceHotkeyBrokerOwner")
 if CloseBrokerReadyPath != "" && FileExist(CloseBrokerReadyPath)
  try FileDelete(CloseBrokerReadyPath)
 CloseBrokerReadyPath := ""
}
StopCloseWorker(*) {
 global CloseBrokerHWND,CloseBrokerToken,CloseBrokerHandle,CloseBrokerReady,CloseBusy,BrokerPending,BrokerPhase
 SetTimer(PollCloseBrokerReady,0), SetTimer(WatchCloseWorker,0)
 BrokerPending := 0, CloseBusy := false, CloseBrokerReady := false
 if CloseBrokerHWND
  DllCall("PostMessageW","Ptr",CloseBrokerHWND,"UInt",0x9001,"Ptr",A_ScriptHwnd,"Ptr",CloseBrokerToken)
 if CloseBrokerHandle && DllCall("WaitForSingleObject","Ptr",CloseBrokerHandle,"UInt",500) != 0
  DllCall("TerminateProcess","Ptr",CloseBrokerHandle,"UInt",125)
 ReleaseBrokerHandles()
 BrokerPhase := "idle"
}
WriteCloseStatus() {
 global RuntimeState,CloseKey,CloseLastResult,CloseLastRequested,CloseLatencyMs,CloseBrokerPID,CloseBrokerReady
 global BrokerMode,BrokerLifecycleReady,BrokerPhase,BrokerLastError,BrokerReadyLatencyMs,BrokerRequestLatencyMs,BrokerLastProbeResult
 if IsObject(RuntimeState)
  RuntimeState.Update(Map("CloseKey",CloseKey,"CloseResult",CloseLastResult,"CloseRequestedUTC",CloseLastRequested,"CloseLatencyMs",CloseLatencyMs,
   "CloseBrokerPID",CloseBrokerPID,"CloseBrokerReady",CloseBrokerReady ? 1 : 0,"BrokerMode",BrokerMode,"BrokerLifecycleReady",BrokerLifecycleReady ? 1 : 0,
   "BrokerPhase",BrokerPhase,"BrokerLastError",BrokerLastError,"BrokerReadyLatencyMs",BrokerReadyLatencyMs,"BrokerRequestLatencyMs",BrokerRequestLatencyMs,"BrokerLastProbeResult",BrokerLastProbeResult))
}
