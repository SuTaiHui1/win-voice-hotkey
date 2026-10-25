#Requires AutoHotkey v2.0
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
OnError((problem,*) => (FileAppend(problem.Message "`n" problem.Stack,"**"),ExitApp(1)))
#Include RuntimeState.ahk
global DataDir := A_ScriptDir
global Count := 0
Check(ok, name) {
    global Count
    if !ok
        throw Error(name)
    Count += 1
}
NoWrite(*) {
}
BadRead(*) => "stale cached snapshot"
folder := A_ScriptDir "\state-unit"
DirCreate(folder)
path := folder "\mapping-state.ini"
AtomicRuntimeWrite(path,"[State]`r`nRunning=1`r`nPID=999999`r`nInstanceToken=9`r`nReady=1`r`n",1)
store := RuntimeStateStore(folder,123,456)
store.Publish()
values := ParseRuntimeState(ReadRuntimeFile(path))
Check(values["PID"] = DllCall("GetCurrentProcessId","UInt"),"startup replaces old PID")
Check(values["Running"] = "0" && values["Ready"] = "0" && values["Phase"] = "starting","startup is not ready before initialization")
store.Update(Map("MainReady",1,"CloseBrokerReady",0))
Check(ParseRuntimeState(ReadRuntimeFile(path))["Ready"] = "0","main initialization alone cannot claim broker ready")
store.Update(Map("CloseBrokerReady",1,"CloseBrokerPID",321))
values := ParseRuntimeState(ReadRuntimeFile(path))
Check(values["Running"] = "1" && values["Ready"] = "1" && values["Phase"] = "ready","complete ready snapshot")
Check(values["PID"] = store.PID && values["InstanceToken"] = "456","snapshot identity and lifecycle stay coherent")
Check(!FileExist(path ".new." store.PID),"temporary file is removed")
RuntimeState := store
AtomicRuntimeWrite(path,"[State]`r`nRunning=1`r`nPID=999999`r`n",1)
CheckRuntimeState()
Check(ParseRuntimeState(ReadRuntimeFile(path))["PID"] = store.PID,"health check repairs a replaced snapshot")
Check(InStr(FileRead(folder "\lifecycle.log"),"state_republished"),"replacement is logged without support diagnostics")
FileDelete(path)
CheckRuntimeState()
Check(ParseRuntimeState(ReadRuntimeFile(path))["PID"] = store.PID,"missing snapshot is republished without terminating the runtime")
store.Stop("test_exit",0)
values := ParseRuntimeState(ReadRuntimeFile(path))
Check(values["Running"] = "0" && values["Ready"] = "0" && values["CloseBrokerReady"] = "0","normal exit clears running and readiness")
Check(values["Phase"] = "stopped" && values["ExitReason"] = "test_exit","terminal exit reason persists")
Check(InStr(FileRead(folder "\lifecycle.log"),"event=stopped"),"normal exit is always logged")
failed := RuntimeStateStore(folder,124,457)
failed.Publish()
failed.Fail("synthetic_initialization_failure")
failed.Stop("Error",7)
values := ParseRuntimeState(ReadRuntimeFile(path))
Check(values["Phase"] = "failed" && values["Running"] = "0" && values["ExitCode"] = "7","failed startup cannot become stopped-ready or success")
Check(InStr(FileRead(folder "\lifecycle.log"),"synthetic_initialization_failure"),"startup failure is always logged")
for method in [NoWrite, BadRead] {
    trial := RuntimeStateStore(folder,125,458)
    rejected := false
    try trial.Publish(method = NoWrite ? NoWrite : 0,method = BadRead ? BadRead : 0)
    catch
        rejected := true
    Check(rejected && trial.Failed,"a successful-looking write with stale readback is rejected")
    trial.Stop("test",1)
    if FileExist(path)
        Check(ParseRuntimeState(ReadRuntimeFile(path))["Ready"] = "0","failed publication leaves no ready snapshot")
}
locked := RuntimeStateStore(folder,126,459)
locked.Publish()
before := ReadRuntimeFile(path)
handle := DllCall("CreateFileW","Str",path,"UInt",0x80000000,"UInt",3,"Ptr",0,"UInt",3,"UInt",0x80,"Ptr",0,"Ptr")
Check(handle != -1,"lock fixture opened")
try {
    rejected := false
    try locked.Update(Map("MainReady",1,"CloseBrokerReady",1))
    catch
        rejected := true
    Check(rejected && locked.Failed && ReadRuntimeFile(path) = before,"rename failure is reported and original remains complete")
    Check(!FileExist(path ".new." locked.PID),"rename failure cleans temporary snapshot")
} finally DllCall("CloseHandle","Ptr",handle)
locked.Stop("test",1)
idle := RuntimeStateStore(folder,127,460)
idle.Update(Map("MainReady",1,"BrokerMode","on_demand","BrokerLifecycleReady",1,"BrokerPhase","idle"))
values := ParseRuntimeState(ReadRuntimeFile(path))
Check(values["Ready"] = "1" && values["CloseBrokerReady"] = "0","on-demand standby is operational without a resident broker")
idle.Update(Map("BrokerPhase","starting"))
Check(ParseRuntimeState(ReadRuntimeFile(path))["Ready"] = "1","queued cold startup does not report application failure")
idle.Stop("test",0)
Check(ParseRuntimeState(ReadRuntimeFile(path))["Ready"] = "0","on-demand application exit still clears readiness")
FileAppend('{"passed":' Count ',"hooks_installed":false,"microphone_used":false,"voice_sent":false}',A_ScriptDir "\runtime-state-unit-results.json","UTF-8-RAW")
ExitApp()
