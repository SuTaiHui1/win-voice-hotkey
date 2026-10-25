using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class Launcher {
    delegate bool EnumWindow(IntPtr window,IntPtr arg);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr arg);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetProp(IntPtr window,string name);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct StartupInfo {public int Size;public string Reserved,Desktop,Title;public int X,Y,Width,Height,XChars,YChars,Fill,Flags;public short Show,ReservedSize;public IntPtr ReservedData,Input,Output,Error;}
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {public IntPtr Process,Thread;public uint PID,TID;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inheritHandles,uint flags,IntPtr environment,string directory,ref StartupInfo startup,out ProcessInfo process);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
    static Process StartWithoutCallerStreams(ProcessStartInfo start) {
        var entries=new List<string>();
        foreach(System.Collections.DictionaryEntry entry in start.EnvironmentVariables)entries.Add(entry.Key+"="+entry.Value);
        entries.Sort(StringComparer.OrdinalIgnoreCase);
        IntPtr environment=Marshal.StringToHGlobalUni(String.Join("\0",entries.ToArray())+"\0\0");
        var startup=new StartupInfo{Size=Marshal.SizeOf(typeof(StartupInfo)),Flags=0x100};
        ProcessInfo created;
        try {
            // No inherited handles, including duplicate redirected handles which are
            // not the launcher's current standard handles. No caller pipe survives.
            if(!CreateProcess(start.FileName,new StringBuilder("\""+start.FileName+"\" "+start.Arguments),IntPtr.Zero,IntPtr.Zero,false,0x08000404,environment,start.WorkingDirectory,ref startup,out created))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            try {var process=Process.GetProcessById((int)created.PID);IntPtr retained=process.Handle;if(ResumeThread(created.Thread)==UInt32.MaxValue)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());return process;}
            catch {TerminateProcess(created.Process,126);throw;}
            finally {CloseHandle(created.Thread);CloseHandle(created.Process);}
        } finally {Marshal.FreeHGlobal(environment);}
    }
    sealed class Instance { public int PID; public IntPtr Window; public long Token; }
    static Dictionary<string,string> State(string data) {
        var result=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        string path=Path.Combine(data,"mapping-state.ini");if(!File.Exists(path))return result;
        bool state=false;
        foreach(string line in File.ReadAllLines(path)) {
            string text=line.Trim();if(text.StartsWith("[")){state=text.Equals("[State]",StringComparison.OrdinalIgnoreCase);continue;}
            int at=text.IndexOf('=');if(state&&at>0)result[text.Substring(0,at)]=text.Substring(at+1);
        }
        return result;
    }
    static string Read(Dictionary<string,string> state,string key) { string value;return state.TryGetValue(key,out value)?value:"0"; }
    internal static string Data(string root) {
        var value=Environment.GetEnvironmentVariable("WIN_VOICE_HOTKEY_DATA_DIR");
        return !String.IsNullOrEmpty(value)?Path.GetFullPath(value):File.Exists(Path.Combine(root,"portable.flag"))?Path.Combine(root,"data"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"WinVoiceHotkey");
    }
    static bool Owned(int pid,string root) {
        try {using(var p=Process.GetProcessById(pid))return p.SessionId==Process.GetCurrentProcess().SessionId&&String.Equals(p.MainModule.FileName,Path.GetFullPath(Path.Combine(root,"app","dependencies","AutoHotkey64.exe")),StringComparison.OrdinalIgnoreCase);}catch{return false;}
    }
    static List<Instance> Instances(string root) {
        var found=new List<Instance>();
        EnumWindows((window,arg)=>{long token=GetProp(window,"WinVoiceHotkeyInstance").ToInt64();if(token==0)return true;uint pid;GetWindowThreadProcessId(window,out pid);if(Owned((int)pid,root))found.Add(new Instance{PID=(int)pid,Window=window,Token=token});return true;},IntPtr.Zero);
        return found;
    }
    static Instance Verify(Dictionary<string,string> state,string root) {
        int pid;long hwnd,token;uint actual;
        if(!int.TryParse(Read(state,"PID"),out pid)||!long.TryParse(Read(state,"HWND"),out hwnd)||!long.TryParse(Read(state,"InstanceToken"),out token)||pid<=0||hwnd==0||token==0)return null;
        var window=new IntPtr(hwnd);GetWindowThreadProcessId(window,out actual);
        return actual==pid&&GetProp(window,"WinVoiceHotkeyInstance").ToInt64()==token&&Owned(pid,root)?new Instance{PID=pid,Window=window,Token=token}:null;
    }
    static int WaitReady(string root,string data,int pid,Process child) {
        DateTime until=DateTime.UtcNow.AddSeconds(8);
        do {
            var state=State(data);var instance=Verify(state,root);
            if(instance!=null&&instance.PID==pid&&Read(state,"Running")=="1"&&Read(state,"Ready")=="1"&&Read(state,"Phase")=="ready"&&(Read(state,"CloseBrokerReady")=="1"||(Read(state,"BrokerMode")=="on_demand"&&Read(state,"BrokerLifecycleReady")=="1")))return 0;
            if(child!=null&&child.HasExited)return StopError(child.ExitCode==0?2:child.ExitCode,"程序在就绪前退出；请查看 lifecycle.log。 / Runtime exited before verified readiness.");
            if(Read(state,"PID")==pid.ToString()&&Read(state,"Phase")=="failed")return StopError(2,"程序初始化失败；请查看 lifecycle.log。 / Runtime initialization failed.");
            Thread.Sleep(40);
        }while(DateTime.UtcNow<until);
        return StopError(3,"未能确认程序及状态就绪；未启动第二个实例。 / Readiness not confirmed; no second instance was launched.");
    }
    static int StopError(int code,string message) {WriteError(message);return code;}
    internal static void WriteError(string message) {
        try {byte[] bytes=Encoding.UTF8.GetBytes(message+Environment.NewLine);using(var stream=Console.OpenStandardError()){stream.Write(bytes,0,bytes.Length);stream.Flush();}}catch{}
    }
    static void StartupFailure(string data,int pid,int code,string detail) {
        try {Directory.CreateDirectory(data);string path=Path.Combine(data,"lifecycle.log");if(File.Exists(path)&&new FileInfo(path).Length>131072){string old=Path.Combine(data,"lifecycle.previous.log");if(File.Exists(old))File.Delete(old);File.Move(path,old);}File.AppendAllText(path,DateTime.UtcNow.ToString("yyyyMMddHHmmss")+" event=launcher_start_failed pid="+pid+" code="+code+" detail="+detail.Replace('\r',' ').Replace('\n',' ')+Environment.NewLine,new UTF8Encoding(false));}catch{}
    }
    internal static int StopAndConfirm(string data,string root=null) {
        root=root??AppDomain.CurrentDomain.BaseDirectory;
        var state=State(data);Instance instance=null;
        if(state.Count>0) {
            int pid;long token;
            if(!int.TryParse(Read(state,"PID"),out pid)||pid<=0||!long.TryParse(Read(state,"InstanceToken"),out token)||token==0)return StopError(2,"退出状态无效，未发送请求。 / Invalid instance state.");
            bool exists;try{using(var p=Process.GetProcessById(pid))exists=true;}catch(ArgumentException){exists=false;}
            if(exists){instance=Verify(state,root);if(instance==null)return StopError(2,"退出目标校验失败，未发送请求。 / Instance identity mismatch.");}
        }
        if(instance==null) {
            var live=Instances(root);if(live.Count==0)return 0;
            if(live.Count!=1)return StopError(2,"发现不明确的运行实例，未发送请求。 / Ambiguous live instance.");
            instance=live[0]; // Stale/absent PID is not evidence that this installation has no live owner.
        }
        using(var target=Process.GetProcessById(instance.PID)) {
            IntPtr retained=target.Handle;
            if(GetProp(instance.Window,"WinVoiceHotkeyInstance").ToInt64()!=instance.Token||!PostMessage(instance.Window,0x805E,IntPtr.Zero,IntPtr.Zero))return StopError(2,"退出核验或发送失败。 / Stop request failed.");
            if(!target.WaitForExit(3000))return StopError(3,"已请求退出，但等待超时。 / Exit wait timed out.");
        }
        if(Instances(root).Count!=0)return StopError(3,"仍有实例，未确认退出。 / A live instance remains.");
        var stopped=State(data);
        if(stopped.Count>0&&(Read(stopped,"Running")!="0"||Read(stopped,"Ready")=="1"))return StopError(2,"进程已退出，但退出记录未刷新。 / Process exited, but terminal state is stale.");
        return 0;
    }
    [STAThread] static int Main(string[] args) {
        string action=args.Length==0?"":args[0];
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory,data=Data(root);
            if(action=="--stop")return StopAndConfirm(data,root);
            if(action!=""&&action!="--settings"&&action!="--smoke-test")return 64;
            if(action!="--smoke-test") {
                var existing=Instances(root);
                if(existing.Count>1)return StopError(2,"已有多个实例，未继续启动。 / Multiple existing instances.");
                if(existing.Count==1){int ready=WaitReady(root,data,existing[0].PID,null);if(ready==0&&action=="--settings")PostMessage(existing[0].Window,0x805F,IntPtr.Zero,IntPtr.Zero);return ready;}
            }
            Directory.CreateDirectory(data);string config=Path.Combine(data,"config.ini");
            if(!File.Exists(config))File.WriteAllText(config,"[Mapping]\r\nEnabled=1\r\nKey=XButton1\r\nCloseKey=XButton2\r\n",Encoding.Unicode);
            string runtime=Path.Combine(root,"app","dependencies","AutoHotkey64.exe"),script=Path.Combine(root,"app","WinHGate.ahk");
            if(!File.Exists(runtime)||!File.Exists(script))throw new FileNotFoundException("请完整解压发行包后运行。 / Extract the complete package first.");
            var start=new ProcessStartInfo(runtime,"/ErrorStdOut \""+script+"\" "+action){UseShellExecute=false,WorkingDirectory=Path.Combine(root,"app"),CreateNoWindow=true};
            start.EnvironmentVariables["WIN_VOICE_HOTKEY_DATA_DIR"]=data;
            using(var child=StartWithoutCallerStreams(start)) {
                if(action=="--smoke-test") {
                    if(!child.WaitForExit(15000)){StartupFailure(data,child.Id,3,"smoke timeout");return StopError(3,"无输入检查未在时限内结束。 / Smoke timeout.");}
                    if(child.ExitCode!=0){StartupFailure(data,child.Id,child.ExitCode,"runtime exited before verified readiness; see runtime lifecycle events");return child.ExitCode;}
                    var terminal=State(data);return Read(terminal,"PID")==child.Id.ToString()&&Read(terminal,"Running")=="0"&&Read(terminal,"Ready")=="0"?0:StopError(2,"检查结束但状态未刷新。 / Stale smoke terminal state.");
                }
                int result=WaitReady(root,data,child.Id,child);
                if(result!=0)StartupFailure(data,child.Id,result,"runtime exited before verified readiness; see runtime lifecycle events");
                return result;
            }
        } catch(Exception error) {
            WriteError(error.Message);
            if(action=="")try{MessageBox.Show(error.Message,"Win Voice Hotkey",MessageBoxButtons.OK,MessageBoxIcon.Error);}catch{}
            return 1;
        }
    }
}
