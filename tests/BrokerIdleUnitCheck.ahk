#Requires AutoHotkey v2.0
#Include BrokerIdlePolicy.ahk
passed := 0
Check(ok,label) {
 global passed
 if !ok {
  FileAppend(label,"**")
  ExitApp(1)
 }
 passed += 1
}
l := BrokerIdleLease(10000)
Check(!l.CanReclaim(50000,false,false,false,false),"unverified absence never reclaims")
l.Touch(1000), l.Observe("panel_absent",2000)
Check(!l.CanReclaim(11999,false,false,false,false),"absence must be stable for grace")
Check(l.CanReclaim(12000,false,false,false,false),"stable absence can reclaim")
for guard in [1,2,3,4] {
 flags := [false,false,false,false], flags[guard] := true
 Check(!l.CanReclaim(13000,flags*),"busy queued opening and language preparation pin lease")
}
l.Touch(12000)
Check(!l.CanReclaim(13000,false,false,false,false),"new user request extends lease")
for status in ["panel_present","panel_not_ready","ambiguous_panel","rejected","no_verified_panel","close_not_confirmed","helper_timeout_no_other_action","helper_result_unknown"] {
 l.Observe(status,24000)
 Check(!l.CanReclaim(50000,false,false,false,false),"uncertain or present result cannot reclaim " status)
 l.Observe("panel_absent",50000)
 Check(!l.CanReclaim(50001,false,false,false,false),"new absence restarts stable grace " status)
}
l.Observe("panel_absent",60000)
Check(l.CanReclaim(60000,false,false,false,false),"repeated absence preserves first verified tick")
l.Invalidate()
Check(!l.CanReclaim(90000,false,false,false,false),"native panel or dispatched open invalidates stale absence")
l.Observe("closed",90000)
Check(l.CanReclaim(100000,false,false,false,false),"verified close starts grace")
FileAppend('{"passed":' passed ',"voice_sent":false,"microphone_used":false}',A_ScriptDir "\broker-idle-unit-results.json","UTF-8-RAW")
ExitApp()