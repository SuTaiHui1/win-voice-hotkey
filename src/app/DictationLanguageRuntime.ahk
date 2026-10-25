#Include DictationLanguagePolicy.ahk
; Native language requests target only the current focused window's input thread.
global DictationLanguageIO := NativeDictationLanguageIO(), ChineseLanguageGate := ChineseLanguagePreparation()
class NativeDictationLanguageIO {
 Capture() {
  window := DllCall("GetForegroundWindow","Ptr")
  if !window
   return 0
  pid := 0
  thread := DllCall("GetWindowThreadProcessId","Ptr",window,"UInt*",&pid,"UInt")
  info := Buffer(8+6*A_PtrSize+16,0), NumPut("UInt",info.Size,info)
  if !thread || !DllCall("GetGUIThreadInfo","UInt",thread,"Ptr",info) || (NumGet(info,4,"UInt") & 0x1E)
   return 0
  focus := NumGet(info,8+A_PtrSize,"Ptr")
  if !focus || DllCall("GetAncestor","Ptr",focus,"UInt",2,"Ptr") != window
   return 0
  thread := DllCall("GetWindowThreadProcessId","Ptr",focus,"UInt*",&pid,"UInt")
  if !thread
   return 0
  try name := ProcessGetName(pid)
  catch
   return 0
  if RegExMatch(name,"i)^(TextInputHost|StartMenuExperienceHost|SearchHost)\.exe$")
   return 0
  return {Window:window,Focus:focus,Thread:thread,PID:pid,HKL:DllCall("GetKeyboardLayout","UInt",thread,"Ptr")}
 }
 Layouts() {
  n := DllCall("GetKeyboardLayoutList","Int",0,"Ptr",0,"Int"), result := []
  if n <= 0
   return result
  list := Buffer(n*A_PtrSize)
  n := DllCall("GetKeyboardLayoutList","Int",n,"Ptr",list,"Int")
  Loop n
   result.Push(NumGet(list,(A_Index-1)*A_PtrSize,"Ptr"))
  return result
 }
 Request(target,layout) {
  current := this.Capture()
  if !SameDictationTarget(target,current) || current.HKL != target.HKL
   return false
  return DllCall("PostMessageW","Ptr",target.Focus,"UInt",0x50,"Ptr",0,"Ptr",layout)
 }
 Now() => A_TickCount
 Schedule(enabled) {
  SetTimer(CheckChineseDictation,enabled ? 20 : 0)
 }
}
DictationPreparationAllowed(generation) {
 global SettingsOpen,RecoveryPaused,InputState
 return !SettingsOpen && !RecoveryPaused && IsObject(InputState) && generation = InputState.Generation && !ModifiersHeld()
}
SetDictationLanguageResult(result,notify := false) {
 global RuntimeState
 ; All outcomes remain in passive status only; never announce language preparation.
 ; Keep the optional argument for existing callers, without changing their outcome.
 if IsObject(RuntimeState)
  RuntimeState.Update(Map("DictationLanguage","zh-CN","LanguageResult",result,"LanguageRestore","manual"))
}
BeginChineseDictation(target := unset) {
 global DictationLanguageIO,ChineseLanguageGate,InputState
 if IsObject(ChineseLanguageGate.Pending)
  return false
 current := DictationLanguageIO.Capture()
 if !IsSet(target)
  target := current
 if !IsObject(current) || !IsObject(target) {
  FailChineseDictation("no_target")
  return false
 }
 if !SameDictationTarget(target,current) {
  FailChineseDictation("focus_changed")
  return false
 }
 if current.HKL != target.HKL {
  FailChineseDictation("user_language_changed")
  return false
 }
 if !IsObject(InputState) || !DictationPreparationAllowed(InputState.Generation)
  return false
 layout := ChooseChineseLayout(DictationLanguageIO.Layouts(),current.HKL)
 if !layout {
  FailChineseDictation("missing_chinese")
  return false
 }
 state := ChineseLanguageGate.Begin(target,layout,InputState.Generation,DictationLanguageIO.Now())
 if state = "ready"
  return CompleteChineseDictation()
 if !DictationLanguageIO.Request(target,layout) {
  FailChineseDictation("switch_request_failed")
  return false
 }
 SetDictationLanguageResult("switching")
 DictationLanguageIO.Schedule(true)
 return true
}
CheckChineseDictation(*) {
 global DictationLanguageIO,ChineseLanguageGate,InputState
 if !IsObject(ChineseLanguageGate.Pending) {
  DictationLanguageIO.Schedule(false)
  return
 }
 generation := IsObject(InputState) ? InputState.Generation : 0
 state := ChineseLanguageGate.Observe(DictationLanguageIO.Capture(),generation,DictationLanguageIO.Now(),DictationPreparationAllowed(generation))
 if state = "ready"
  CompleteChineseDictation()
 else if state != "pending"
  FailChineseDictation(state)
}
CompleteChineseDictation() {
 global DictationLanguageIO,ChineseLanguageGate,VoiceDispatchSink,ActionState
 p := ChineseLanguageGate.Pending
 if !IsObject(p)
  return false
 SetDictationLanguageResult("ready")
 ; Check again immediately before sending. No activation, layout restore or file I/O follows this check.
 current := DictationLanguageIO.Capture()
 if !DictationPreparationAllowed(p.Generation) {
  FailChineseDictation("cancelled")
  return false
 }
 if !SameDictationTarget(p.Target,current) {
  FailChineseDictation("focus_changed")
  return false
 }
 if !IsSimplifiedChineseLayout(current.HKL) {
  FailChineseDictation("user_language_changed")
  return false
 }
 ChineseLanguageGate.Cancel(), DictationLanguageIO.Schedule(false)
 ActionState.OpeningUntil := DictationLanguageIO.Now()+5000
 if IsObject(VoiceDispatchSink)
  VoiceDispatchSink.Call()
 else {
  BrokerVoiceOpenDispatched()
  Send("#h")
  SetTimer(PollOpeningPanel,250)
 }
 return true
}
FailChineseDictation(result) {
 global ChineseLanguageGate,DictationLanguageIO,ActionState
 ChineseLanguageGate.Cancel(), DictationLanguageIO.Schedule(false)
 ActionState.OpeningUntil := 0, ActionState.Cancel()
 SetTimer(PollOpeningPanel,0)
 SetDictationLanguageResult(result,result != "cancelled")
}
StopChineseDictation(*) {
 global ChineseLanguageGate,DictationLanguageIO
 ChineseLanguageGate.Cancel(), DictationLanguageIO.Schedule(false)
}