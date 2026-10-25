; Pure, bounded preparation policy. It never changes focus or restores a layout.
IsSimplifiedChineseLayout(hkl) => hkl && (hkl & 0xFFFF) = 0x0804
ChooseChineseLayout(layouts, current := 0) {
 if IsSimplifiedChineseLayout(current)
  return current
 for hkl in layouts
  if IsSimplifiedChineseLayout(hkl)
   return hkl
 return 0
}
SameDictationTarget(a,b) => IsObject(a) && IsObject(b) && a.Window = b.Window && a.Focus = b.Focus
 && a.Thread = b.Thread && a.PID = b.PID
class ChineseLanguagePreparation {
 __New() {
  this.Pending := 0
 }
 Begin(target, layout, generation, now) {
  this.Pending := {Target:target,Layout:layout,Generation:generation,Deadline:now+1000,ChineseSince:-1,SeenChinese:false}
  return IsSimplifiedChineseLayout(target.HKL) ? "ready" : "request"
 }
 Observe(current,generation,now,allowed := true) {
  p := this.Pending
  if !IsObject(p)
   return "idle"
  if !allowed || generation != p.Generation
   return "cancelled"
  if !SameDictationTarget(p.Target,current)
   return "focus_changed"
  if IsSimplifiedChineseLayout(current.HKL) {
   p.SeenChinese := true
   if p.ChineseSince < 0
    p.ChineseSince := now
   if now-p.ChineseSince >= 50
    return "ready"
  } else if p.SeenChinese || current.HKL != p.Target.HKL
   return "user_language_changed"
  if now >= p.Deadline
   return "switch_timeout"
  return "pending"
 }
 Cancel() {
  this.Pending := 0
 }
}