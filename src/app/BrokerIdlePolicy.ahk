; The lease never infers absence from inactivity alone.
class BrokerIdleLease {
 __New(idleMs := 10000) {
  this.IdleMs := idleMs, this.LastUse := 0, this.AbsentSince := 0, this.Absent := false
 }
 Touch(now) {
  this.LastUse := now
 }
 Invalidate() {
  this.Absent := false, this.AbsentSince := 0
 }
 Observe(status,now) {
  if status = "panel_absent" || status = "closed" {
   if !this.Absent
    this.AbsentSince := now
   this.Absent := true
  } else
   this.Invalidate()
 }
 CanReclaim(now,busy := false,queued := false,opening := false,preparing := false) {
  return this.Absent && now-this.LastUse >= this.IdleMs && now-this.AbsentSince >= this.IdleMs
   && !busy && !queued && !opening && !preparing
 }
}