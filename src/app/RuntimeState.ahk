; Runtime snapshots deliberately use file I/O, never the legacy Windows profile API.
global RuntimeState := 0

class RuntimeStateStore {
    __New(folder, hwnd, token) {
        this.Folder := folder, this.Path := folder "\mapping-state.ini"
        this.PID := DllCall("GetCurrentProcessId", "UInt"), this.Sequence := 0
        this.Sections := Map("State", Map("Running",0,"Ready",0,"Phase","starting","PID",this.PID,
            "HWND",hwnd,"InstanceToken",token,"Version","0.1.3","CandidateBuild","v0.1.3",
            "StateRevision","atomic-v1","StartedUTC",A_NowUTC,"MainReady",0,"CloseBrokerReady",0,"CloseBrokerPID",0), "Tray", Map())
        this.Failed := false, this.Stopped := false, this.Stopping := false
    }
    Update(values, publish := true) {
        for key, value in values
            this.Sections["State"][key] := value
        if publish
            this.Publish()
    }
    Text() {
        text := ""
        for section, values in this.Sections {
            text .= "[" section "]`r`n"
            for key, value in values {
                value := StrReplace(StrReplace(String(value),"`r"," "),"`n"," ")
                text .= key "=" value "`r`n"
            }
        }
        return text
    }
    Publish(writer := 0, reader := 0) {
        previous := A_IsCritical
        Critical("On")
        try {
            state := this.Sections["State"]
            state["PID"] := this.PID, state["UpdatedUTC"] := A_NowUTC, state["Sequence"] := ++this.Sequence
            state["Running"] := !this.Failed && !this.Stopped && !this.Stopping && state["MainReady"] && state["CloseBrokerReady"] ? 1 : 0
            state["Ready"] := state["Running"]
            state["Phase"] := this.Failed ? "failed" : this.Stopped ? "stopped" : this.Stopping ? "stopping" : state["Ready"] ? "ready" : "starting"
            text := this.Text()
            (writer ? writer : AtomicRuntimeWrite)(this.Path, text, this.PID)
            actual := (reader ? reader : ReadRuntimeFile)(this.Path)
            if actual != text
                throw Error("Runtime state read-back did not match the published snapshot.")
        } catch as problem {
            this.Failed := true
            this.Sections["State"]["Running"] := 0, this.Sections["State"]["Ready"] := 0
            this.Sections["State"]["Phase"] := "failed"
            this.Event("state_write_failed", Type(problem) " " problem.Message)
            throw problem
        } finally Critical(previous ? previous : "Off")
    }
    Event(name, detail := "") {
        ; Only lifecycle metadata; no key/voice/foreground-window history.
        path := this.Folder "\lifecycle.log"
        try {
            if FileExist(path) && FileGetSize(path) > 131072
                FileMove(path, this.Folder "\lifecycle.previous.log", 1)
            FileAppend(A_NowUTC " event=" name " pid=" this.PID " phase=" this.Sections["State"]["Phase"]
                (detail = "" ? "" : " detail=" StrReplace(StrReplace(detail,"`r"," "),"`n"," ")) "`n", path, "UTF-8-RAW")
        } catch {
            ; Failure reporting must not recursively fail or depend on support logging.
            try {
                folder := A_Temp "\WinVoiceHotkey-failures"
                DirCreate(folder)
                FileAppend(A_NowUTC " pid=" this.PID " event=" name " detail=" detail "`n", folder "\lifecycle.log", "UTF-8-RAW")
            }
        }
    }
    Fail(reason) {
        this.Failed := true
        this.Update(Map("Failure",reason,"CloseBrokerReady",0))
        this.Event("failed", reason)
    }
    Stop(reason, code) {
        this.Stopped := true, this.Stopping := false
        try this.Update(Map("MainReady",0,"CloseBrokerReady",0,"CloseBrokerPID",0,"ExitReason",reason,"ExitCode",code))
        catch as problem {
            this.Event("stop_publish_failed", Type(problem))
            ; Never knowingly leave our own Ready=1 snapshot after a failed stop publication.
            try {
                old := ParseRuntimeState(ReadRuntimeFile(this.Path))
                if old.Get("PID","0") = this.PID && old.Get("InstanceToken","0") = this.Sections["State"]["InstanceToken"]
                    FileDelete(this.Path)
            }
        }
        this.Event("stopped", "reason=" reason " code=" code)
    }
    BeginStop(reason, code) {
        this.Stopping := true
        this.Update(Map("MainReady",0,"CloseBrokerReady",0,"ExitReason",reason,"ExitCode",code))
        this.Event("stopping", "reason=" reason " code=" code)
    }
}
ReadRuntimeFile(path) => FileRead(path, "UTF-16")
ParseRuntimeState(text) {
    values := Map(), inState := false
    for line in StrSplit(text,"`n","`r") {
        if SubStr(line,1,1) = "[" {
            inState := line = "[State]"
            continue
        }
        at := InStr(line,"=")
        if inState && at > 1
            values[SubStr(line,1,at-1)] := SubStr(line,at+1)
    }
    return values
}
AtomicRuntimeWrite(path, text, pid) {
    temp := path ".new." pid
    try {
        file := FileOpen(temp, "w", "UTF-16")
        try {
            file.Write(text)
            if !DllCall("FlushFileBuffers", "Ptr", file.Handle)
                throw OSError()
        } finally file.Close()
        errorCode := 0
        Loop 3 {
            if DllCall("MoveFileExW", "Str", temp, "Str", path, "UInt", 9)
                return
            errorCode := A_LastError
            Sleep(20)
        }
        throw OSError(errorCode)
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}
InitializeRuntimeState() {
    global RuntimeState, DataDir, StatusToken
    StatusToken := Random(1,2147483647)
    DllCall("SetPropW","Ptr",A_ScriptHwnd,"Str","WinVoiceHotkeyInstance","Ptr",StatusToken)
    RuntimeState := RuntimeStateStore(DataDir,A_ScriptHwnd,StatusToken)
    RuntimeState.Publish()
    RuntimeState.Event("starting")
}
CheckRuntimeState() {
    global RuntimeState
    if !IsObject(RuntimeState) || RuntimeState.Stopped
        return
    actual := ""
    try actual := ReadRuntimeFile(RuntimeState.Path)
    if actual != RuntimeState.Text() {
        RuntimeState.Publish()
        RuntimeState.Event("state_republished", "snapshot was missing or replaced")
    }
}
