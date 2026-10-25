#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#NoTrayIcon
OnError(TestFailure)
#Include RuntimeState.ahk
#Include KeyCatalog.ahk
#Include SupportDiagnostics.ahk
#Include InputRouter.ahk
#Include KeyboardObserver.ahk
#Include GlobalRuntime.ahk
#Include KeySettings.ahk
#Include CloseBrokerRuntime.ahk
global SettingsOpen := false, SettingsWindow := 0, SmokeTest := true, StopRequest := A_ScriptDir "\unused-stop.request"
global DataDir := A_ScriptDir, ConfigPath := A_ScriptDir "\unused-config.ini", TriggerKey := "XButton1"
global ReportPath := A_Args.Length ? A_Args[1] : A_ScriptDir "\native-language-results.json"
global Stage := "initial", Deadline := A_TickCount+7000, Sent := 0, BeforeSent := 0, Passed := 0, LastNotice := ""
global OriginalHKL := 0, EnglishHKL := 0, ChineseHKL := 0, MessageLayouts := [], RestoreConfirmed := false
global NextAfterEnglish := "open", PhaseStarted := A_TickCount
InputState := BindingInputRouter(ResolveKeySpec("XButton1"),ResolveKeySpec("XButton1"))
class CountingLanguageIO extends NativeDictationLanguageIO {
 __New() {
  this.Requests := 0
 }
 Request(target,layout) {
  this.Requests += 1
  return super.Request(target,layout)
 }
}
DictationLanguageIO := CountingLanguageIO()
VoiceDispatchSink := SafeVoiceSink
class NativeStatusFixture {
 Update(values) {
  global LastNotice
  LastNotice := values["LanguageResult"]
 }
}
RuntimeState := NativeStatusFixture()
OnMessage(0x51,RememberLayoutChange)
global TestWindow := Gui("", "中文输入语言验证（不录音、不发送 Win+H）")
TestWindow.AddText("w560", "仅切换这个测试窗口的输入语言。不会录音、发送消息或读取其他应用文本。`n若你切换到其他应用，测试会停止，不抢回焦点。")
global EditA := TestWindow.AddEdit("w560 h55", "独立测试文本框 A")
global EditB := TestWindow.AddEdit("w560 h55", "独立测试文本框 B")
global Info := TestWindow.AddText("w560 h40", "正在等待测试窗口获得焦点…")
TestWindow.OnEvent("Close",(*) => AbortTest("user_closed_test"))
global OtherWindow := Gui("", "中文语言验证：第二个独立测试窗口")
global OtherEdit := OtherWindow.AddEdit("w400 h70", "独立测试文本框 C")
OtherWindow.OnEvent("Close",(*) => AbortTest("user_closed_test"))
TestWindow.Show("w600 h270")
EditA.Focus()
SetTimer(AdvanceTest,20)
WriteMappingStatus(*) {
}
RememberNotice(result) {
 global LastNotice
 LastNotice := result
}
RememberLayoutChange(wParam,lParam,*) {
 global MessageLayouts
 MessageLayouts.Push(lParam)
}
SafeVoiceSink(*) {
 global Sent,DictationLanguageIO
 current := DictationLanguageIO.Capture()
 if !IsObject(current) || !IsSimplifiedChineseLayout(current.HKL)
  throw Error("Shortcut reached test sink without confirmed Chinese")
 Sent += 1
}
NativeCheck(name,okay,detail := "") {
 global Passed,ReportPath
 FileAppend('{"case":"' name '","passed":' (okay ? "true" : "false") ',"detail":"' detail '"}`n',ReportPath ".jsonl","UTF-8-RAW")
 if !okay
  throw Error(name ": " detail)
 Passed += 1
}
OwnTarget() {
 global DictationLanguageIO,TestWindow,OtherWindow
 c := DictationLanguageIO.Capture()
 return IsObject(c) && (c.Window = TestWindow.Hwnd || c.Window = OtherWindow.Hwnd) ? c : 0
}
RequestEnglish(next) {
 global DictationLanguageIO,EnglishHKL,NextAfterEnglish,Stage,Deadline,LastNotice,EditA
 EditA.Focus()
 c := OwnTarget()
 if !IsObject(c)
  return AbortTest("focus_left_test")
 NextAfterEnglish := next, LastNotice := ""
 if c.HKL != EnglishHKL && !DictationLanguageIO.Request(c,EnglishHKL)
  throw Error("Actual English setup request was rejected")
 Stage := "await_english", Deadline := A_TickCount+1500
}
AdvanceTest(*) {
 global Stage,Deadline,DictationLanguageIO,OriginalHKL,EnglishHKL,ChineseHKL,TestWindow,OtherWindow,EditA,EditB,OtherEdit,Info
 global Sent,BeforeSent,NextAfterEnglish,PhaseStarted,LastNotice,ChineseLanguageGate,MessageLayouts,RestoreConfirmed
 try {
  current := OwnTarget()
  if Stage = "initial" {
   if !IsObject(current) {
    if A_TickCount >= Deadline
     AbortTest("test_window_needs_user_focus")
    return
   }
   OriginalHKL := current.HKL
   for hkl in DictationLanguageIO.Layouts() {
    if IsSimplifiedChineseLayout(hkl)
     ChineseHKL := hkl
    else if (hkl & 0x3FF) = 9
     EnglishHKL := hkl
   }
   NativeCheck("both existing Chinese and English layouts found",ChineseHKL && EnglishHKL)
   Info.Text := "正在验证：英文切中文、取消、焦点变化及主动改回英文。"
   RequestEnglish("open")
   return
  }
  if !IsObject(current) {
   rawWindow := DllCall("GetForegroundWindow","Ptr")
   if (Stage = "check_window" || Stage = "await_return_window") && (!rawWindow || rawWindow = TestWindow.Hwnd || rawWindow = OtherWindow.Hwnd) && A_TickCount < Deadline
    return
   return AbortTest("focus_left_test_no_external_window_changed")
  }
  if A_TickCount >= Deadline
   throw Error("Native integration stage timed out: " Stage " notice=" LastNotice)
  if Stage = "await_english" {
   if current.HKL != EnglishHKL
    return
   if NextAfterEnglish = "open" {
    NativeCheck("target editor actually entered English",current.HKL = EnglishHKL,"HKL=" current.HKL)
    BeforeSent := Sent
    DispatchVoiceRequest()
    Stage := "await_chinese_open", Deadline := A_TickCount+2000
   } else if NextAfterEnglish = "cancel" {
    BeforeSent := Sent
    DispatchVoiceRequest()
    DispatchBoundAction(3,InputState.Generation)
    Stage := "check_cancel", PhaseStarted := A_TickCount, Deadline := A_TickCount+1000
   } else if NextAfterEnglish = "focus" {
    BeforeSent := Sent
    DispatchVoiceRequest()
    EditB.Focus()
    CheckChineseDictation()
    NativeCheck("actual focus-control change cancels open",Sent = BeforeSent && !ChineseLanguageGate.Pending && LastNotice = "focus_changed")
    EditA.Focus()
    RequestEnglish("window")
   } else if NextAfterEnglish = "window" {
    BeforeSent := Sent
    DispatchVoiceRequest()
    OtherWindow.Show("w440 h120")
    OtherEdit.Focus()
    Stage := "check_window", Deadline := A_TickCount+1000
   } else if NextAfterEnglish = "override" {
    BeforeSent := Sent, MessageLayouts := []
    DispatchVoiceRequest()
    Stage := "await_chinese_override", Deadline := A_TickCount+1000
   }
   return
  }
  if Stage = "await_chinese_open" {
   if Sent = BeforeSent+1 {
    NativeCheck("actual English-to-Chinese guard completed before shortcut sink",IsSimplifiedChineseLayout(current.HKL),"HKL=" current.HKL)
    before := DictationLanguageIO.Requests, BeforeSent := Sent
    DispatchVoiceRequest()
    NativeCheck("already Chinese opens without a new layout request",Sent = BeforeSent+1 && DictationLanguageIO.Requests = before)
    RequestEnglish("cancel")
   } else if !ChineseLanguageGate.Pending
    throw Error("Actual language preparation failed: " LastNotice)
   return
  }
  if Stage = "check_cancel" {
   if A_TickCount-PhaseStarted < 120
    return
   NativeCheck("second shared-key press cancels pending open",Sent = BeforeSent && !ChineseLanguageGate.Pending)
   RequestEnglish("focus")
   return
  }
  if Stage = "check_window" {
   if current.Window != OtherWindow.Hwnd
    return
   CheckChineseDictation()
   NativeCheck("actual window change cancels open without stealing focus",Sent = BeforeSent && !ChineseLanguageGate.Pending && LastNotice = "focus_changed")
   TestWindow.Show()
   Stage := "await_return_window", Deadline := A_TickCount+1000
   return
  }
  if Stage = "await_return_window" {
   if current.Window != TestWindow.Hwnd
    return
   EditA.Focus()
   RequestEnglish("override")
   return
  }
  if Stage = "await_chinese_override" {
   if !IsSimplifiedChineseLayout(current.HKL)
    return
   NativeCheck("Chinese observed before simulated user override",Sent = BeforeSent && IsObject(ChineseLanguageGate.Pending))
   NativeCheck("own-editor user-override request accepted",DictationLanguageIO.Request(current,EnglishHKL))
   Stage := "check_override", Deadline := A_TickCount+1200
   return
  }
  if Stage = "check_override" {
   if ChineseLanguageGate.Pending
    return
   NativeCheck("user-selected English is not forced back or opened",Sent = BeforeSent && current.HKL = EnglishHKL && (LastNotice = "user_language_changed" || LastNotice = "switch_timeout"),LastNotice)
   if current.HKL != OriginalHKL {
    NativeCheck("test-only original language restore request accepted",DictationLanguageIO.Request(current,OriginalHKL))
    Stage := "restore_test", Deadline := A_TickCount+1000
   } else
    FinishTest()
   return
  }
  if Stage = "restore_test" && current.HKL = OriginalHKL {
   RestoreConfirmed := true
   FinishTest()
  }
 } catch as problem
  TestFailure(problem)
}
FinishTest() {
 global Passed,Sent,ReportPath,OriginalHKL,RestoreConfirmed
 StopActionTimers(), SetTimer(AdvanceTest,0)
 FileAppend('{"all_passed":true,"passed":' Passed ',"actual_input_language_switch_tested":true,"shortcut_sink_calls":' Sent ',"real_WinH_sent":false,"microphone_used":false,"real_UIA_invoked":false,"external_drafts_read_or_written":false,"test_original_hkl":' OriginalHKL ',"test_restore_confirmed":' (RestoreConfirmed ? "true" : "false") '}',ReportPath,"UTF-8-RAW")
 ExitApp()
}
AbortTest(reason) {
 global ReportPath
 StopActionTimers(), SetTimer(AdvanceTest,0)
 FileAppend('{"all_passed":false,"interrupted":true,"reason":"' reason '","real_WinH_sent":false,"microphone_used":false}',ReportPath,"UTF-8-RAW")
 ExitApp(2)
}
TestFailure(problem,*) {
 global ReportPath
 try StopActionTimers()
 try SetTimer(AdvanceTest,0)
 try RestoreOwnTestLanguage()
 try FileAppend(problem.Message "`n" problem.Stack,ReportPath ".error.txt","UTF-8-RAW")
 try FileAppend(problem.Message "`n" problem.Stack,"**")
 ExitApp(1)
}RestoreOwnTestLanguage() {
 global OriginalHKL,DictationLanguageIO
 current := OwnTarget()
 if !OriginalHKL || !IsObject(current) || current.HKL = OriginalHKL
  return
 if !DictationLanguageIO.Request(current,OriginalHKL)
  return
 restoreDeadline := A_TickCount+700
 while A_TickCount < restoreDeadline {
  after := OwnTarget()
  if !SameDictationTarget(current,after) || after.HKL = OriginalHKL
   return
  Sleep(20)
 }
}