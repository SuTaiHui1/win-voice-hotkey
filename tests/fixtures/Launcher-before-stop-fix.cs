using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class Launcher {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    static extern uint GetPrivateProfileString(string section,string key,string fallback,StringBuilder value,uint size,string path);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetProp(IntPtr hwnd,string name);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd,uint msg,IntPtr w,IntPtr l);
    static string Read(string file,string key) { var value=new StringBuilder(128);GetPrivateProfileString("State",key,"0",value,128,file);return value.ToString(); }
    static string Data(string root) {
        var isolated=Environment.GetEnvironmentVariable("WIN_VOICE_HOTKEY_DATA_DIR");
        if(!String.IsNullOrEmpty(isolated))return Path.GetFullPath(isolated);
        return File.Exists(Path.Combine(root,"portable.flag"))?Path.Combine(root,"data"):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"WinVoiceHotkey");
    }
    static bool Signal(string data,uint message) {
        string state=Path.Combine(data,"mapping-state.ini");long hwnd,token;uint pid,actual;
        if(!long.TryParse(Read(state,"HWND"),out hwnd)||!long.TryParse(Read(state,"InstanceToken"),out token)||!uint.TryParse(Read(state,"PID"),out pid)||hwnd==0||token==0)return false;
        GetWindowThreadProcessId(new IntPtr(hwnd),out actual);
        if(actual!=pid||GetProp(new IntPtr(hwnd),"WinVoiceHotkeyInstance").ToInt64()!=token)return false;
        return PostMessage(new IntPtr(hwnd),message,IntPtr.Zero,IntPtr.Zero);
    }
    [STAThread] static int Main(string[] args) {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory,data=Data(root);
            string action=args.Length==0?"":args[0];
            if(action=="--stop") { Signal(data,0x805E);return 0; }
            if(action=="--settings"&&Signal(data,0x805F))return 0;
            if(action!=""&&action!="--settings"&&action!="--smoke-test")return 64;
            Directory.CreateDirectory(data);
            string config=Path.Combine(data,"config.ini");
            if(!File.Exists(config))File.WriteAllText(config,"[Mapping]\r\nEnabled=1\r\nKey=XButton1\r\nCloseKey=XButton2\r\n",Encoding.Unicode);
            string runtime=Path.Combine(root,"app","dependencies","AutoHotkey64.exe"),script=Path.Combine(root,"app","WinHGate.ahk");
            if(!File.Exists(runtime)||!File.Exists(script))throw new FileNotFoundException("请完整解压发行包后运行。 / Extract the complete release package first.");
            var start=new ProcessStartInfo(runtime,"/ErrorStdOut \""+script+"\" "+action) {UseShellExecute=false,WorkingDirectory=Path.Combine(root,"app"),CreateNoWindow=true};
            start.EnvironmentVariables["WIN_VOICE_HOTKEY_DATA_DIR"]=data;
            using(var process=Process.Start(start)) { if(action=="--smoke-test") {if(!process.WaitForExit(15000)){process.Kill();return 124;}return process.ExitCode;} }
            return 0;
        } catch(Exception error) {MessageBox.Show(error.Message,"Win Voice Hotkey",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
    }
}
