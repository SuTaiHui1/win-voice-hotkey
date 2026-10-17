; Actions are queued outside low-level hooks. Shared bindings query actual panel state.
global VoiceDispatchSink := 0, BoundActionNotificationSink := 0
global InputState := 0, RecoveryPaused := false, RecoveryWaiting := false
global ActionState := PanelActionState(), PendingBrokerAction := "close"

class PanelActionState {
    __New() {
        this.Busy := false, this.LastAction := -10000, this.OpeningUntil := 0, this.Presence := "unknown"
    }
    Begin(role, now) {
        if this.Busy || now - this.LastAction < 200
            return ""
        this.LastAction := now
        if role = 1
            return "open"
        this.Busy := true
        return role = 3 ? "toggle" : "close"
    }
    Finish(mode, status, now) {
        this.Busy := false
        if status = "panel_present" || status = "panel_not_ready" {
            this.Presence := "present", this.OpeningUntil := 0
        } else if status = "closed" {
            this.Presence := "absent", this.OpeningUntil := 0
        } else if status = "panel_absent" {
            this.Presence := "absent"
            if mode = "toggle" && now >= this.OpeningUntil {
                this.OpeningUntil := now + 5000
                return "open"
            }
        }
        return ""
    }
    NativeHidden() {
        this.OpeningUntil := 0
    }
    PollNeeded(now) {
        if this.OpeningUntil && now >= this.OpeningUntil
            this.OpeningUntil := 0
        return this.OpeningUntil > now
    }
    Cancel() {
        this.Busy := false
    }
}
ModifiersHeld() {
    global InputState
    return IsObject(InputState) && InputState.OtherModifiers()
}
QueueBoundAction(role, generation) {
    global BoundActionNotificationSink
    if IsObject(BoundActionNotificationSink)
        BoundActionNotificationSink.Call(role, generation)
    else
        DllCall("PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x8060, "Ptr", role, "Ptr", generation)
}
OnBoundAction(role, generation, *) {
    global SettingsOpen, RecoveryPaused, InputState
    if SettingsOpen || RecoveryPaused || !IsObject(InputState) || generation != InputState.Generation
        return
    SetTimer((*) => DispatchBoundAction(role, generation), -15)
}
DispatchBoundAction(role, generation) {
    global SettingsOpen, RecoveryPaused, InputState, ActionState
    if SettingsOpen || RecoveryPaused || generation != InputState.Generation || ModifiersHeld()
        return
    mode := ActionState.Begin(role, A_TickCount)
    if mode = "open"
        DispatchVoiceRequest()
    else if mode != "" && !StartCloseWorker(mode)
        ActionState.Cancel()
}
DispatchVoiceRequest() {
    global VoiceDispatchSink
    if IsObject(VoiceDispatchSink) {
        VoiceDispatchSink.Call()
        return
    }
    Send("#h")
}
PanelActionCompleted(mode, status) {
    global ActionState, SettingsOpen, RecoveryPaused
    SupportLog("panel_result", "mode=" mode " status=" status)
    next := ActionState.Finish(mode, status, A_TickCount)
    if next = "open" && !SettingsOpen && !RecoveryPaused {
        DispatchVoiceRequest()
        SetTimer(PollOpeningPanel, 250)
    }
    if !ActionState.PollNeeded(A_TickCount)
        SetTimer(PollOpeningPanel, 0)
}
PollOpeningPanel(*) {
    global ActionState, SettingsOpen, RecoveryPaused, CloseBusy
    if !ActionState.PollNeeded(A_TickCount) {
        SetTimer(PollOpeningPanel, 0)
        return
    }
    if SettingsOpen || RecoveryPaused || CloseBusy || ActionState.Busy
        return
    ActionState.Busy := true
    if !StartCloseWorker("presence")
        ActionState.Cancel()
}
RefreshGate() {
    global StopRequest
    if FileExist(StopRequest) {
        FileDelete(StopRequest)
        ExitApp()
    }
}
EmergencyOpenSettings(*) {
    global RecoveryPaused, RecoveryWaiting, InputState
    RecoveryPaused := true, RecoveryWaiting := true
    if IsObject(InputState)
        InputState.Pause()
    SetTimer(WaitRecoveryRelease, 50)
}
WaitRecoveryRelease(*) {
    for key in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "F12"]
        if GetKeyState(key, "P") || GetKeyState(key)
            return
    SetTimer(WaitRecoveryRelease, 0)
    global RecoveryWaiting
    RecoveryWaiting := false
    OpenKeySettings()
}
StopActionTimers(*) {
    SetTimer(PollOpeningPanel, 0)
    SetTimer(WaitRecoveryRelease, 0)
}
ReleaseRestoredKey(*) {
}
GlobalPressAllowed(injected, down, settings, modifiers, nativeHeld, held) =>
    !injected && down && !settings && (held || (!nativeHeld && !modifiers))
