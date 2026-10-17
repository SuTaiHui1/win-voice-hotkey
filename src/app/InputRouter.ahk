; Pure event routing. Only bound-key latches and eight modifier bits are retained.
class BindingInputRouter {
    __New(open, close := 0) {
        this.Held := Map(), this.Modifiers := Map(), this.PendingModifiers := Map(), this.PulseTicks := Map(), this.PulseConsumed := Map()
        this.Generation := 1
        this.Configure(open, close)
    }
    Configure(open, close := 0) {
        this.Open := open, this.Close := close
        this.PendingModifiers.Clear(), this.PulseTicks.Clear()
        this.Generation += 1
    }
    Pause() {
        this.PendingModifiers.Clear()
        this.Generation += 1
    }
    HasHeld() => this.Held.Count > 0 || this.PendingModifiers.Count > 0
    Matches(spec, vk, sc, mouse) => IsObject(spec) && spec.Mouse = mouse
        && (mouse || spec.Modifier || !spec.SC ? spec.VK = vk : spec.SC = sc)
    Role(vk, sc, mouse) {
        open := this.Matches(this.Open, vk, sc, mouse), close := this.Matches(this.Close, vk, sc, mouse)
        return open && close ? 3 : open ? 1 : close ? 2 : 0
    }
    OtherModifiers(vk := 0) {
        for other, held in this.Modifiers
            if held && other != vk
                return true
        return false
    }
    SeedModifier(vk, down) {
        if down
            this.Modifiers[vk] := true
    }
    Handle(vk, sc, down, injected, now, paused := false, mouse := false, pulse := false, otherKeyDown := false) {
        result := {Consume: false, Action: 0, Generation: this.Generation}
        if injected
            return result
        modifier := !mouse && ((vk >= 0xA0 && vk <= 0xA5) || vk = 0x5B || vk = 0x5C)
        modifierAlreadyDown := modifier && this.Modifiers.Has(vk)
        if down {
            for pendingVK, pending in this.PendingModifiers
                if mouse || pendingVK != vk
                    pending.Used := true
        }
        if modifier {
            if down
                this.Modifiers[vk] := true
            else if this.Modifiers.Has(vk)
                this.Modifiers.Delete(vk)
        }
        identity := (mouse ? "m" : "k") ":" vk ":" sc
        role := this.Role(vk, sc, mouse)
        if !down && this.PulseConsumed.Has(identity) {
            tick := this.PulseConsumed.Delete(identity)
            result.Consume := now - tick <= 500
            return result
        }
        if !down && this.Held.Has(identity) {
            result.Consume := this.Held[identity].Consume
            this.Held.Delete(identity)
            return result
        }
        if modifier {
            if !down {
                if this.PendingModifiers.Has(vk) {
                    pending := this.PendingModifiers.Delete(vk)
                    if !paused && !pending.Used && !this.OtherModifiers() && !otherKeyDown
                        result.Action := role
                }
            } else if role && !paused && !this.PendingModifiers.Has(vk)
                this.PendingModifiers[vk] := {Used: modifierAlreadyDown || this.OtherModifiers(vk) || otherKeyDown}
            return result ; Modifier edges remain native so ordinary combinations and recovery work.
        }
        if !role
            return result
        if this.Held.Has(identity) {
            result.Consume := this.Held[identity].Consume
            if !pulse
                return result
        }
        if !down
            return result
        if paused || this.OtherModifiers() {
            if !pulse
                this.Held[identity] := {Consume: false}
            return result
        }
        result.Consume := true
        if pulse {
            if !mouse
                this.PulseConsumed[identity] := now
            last := this.PulseTicks.Has(identity) ? this.PulseTicks[identity] : -10000
            this.PulseTicks[identity] := now
            ; A wheel burst is one gesture: each pulse extends the quiet-gap gate.
            if now - last < 250
                return result
        } else
            this.Held[identity] := {Consume: true}
        result.Action := role
        return result
    }
}
