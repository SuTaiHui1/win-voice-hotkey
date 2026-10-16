// Test-only process host. Never switches the user's visible desktop.
using System;
using System.Runtime.InteropServices;
internal static class TestDesktop {
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    struct StartupInfo {public int cb;public string reserved;public string desktop;public string title;public int x,y,xSize,ySize,xChars,yChars,fill,flags;public short show,reservedSize;public IntPtr reservedData,input,output,error;}
    [StructLayout(LayoutKind.Sequential)]struct ProcessInfo {public IntPtr process,thread;public uint pid,tid;}
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateDesktop(string name,IntPtr device,IntPtr mode,uint flags,uint access,IntPtr security);
    [DllImport("user32.dll")]static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string app,string command,IntPtr ps,IntPtr ts,bool inherit,uint flags,IntPtr environment,string folder,ref StartupInfo startup,out ProcessInfo info);
    [DllImport("kernel32.dll")]static extern IntPtr GetStdHandle(int which);
    [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr handle,uint timeout);
    [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr process,out uint code);
    [DllImport("kernel32.dll")]static extern bool TerminateProcess(IntPtr process,uint code);
    [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
    static int Main(string[] args) {
        if(args.Length!=2)return 64;
        string name="WinVoiceHotkeyTest_"+Guid.NewGuid().ToString("N");
        IntPtr desktop=CreateDesktop(name,IntPtr.Zero,IntPtr.Zero,0,0x01ff,IntPtr.Zero);
        if(desktop==IntPtr.Zero){Console.Error.WriteLine("CreateDesktop failed: "+Marshal.GetLastWin32Error());return 1;}
        try {
            var startup=new StartupInfo {cb=Marshal.SizeOf(typeof(StartupInfo)),desktop=name,flags=0x100,input=GetStdHandle(-10),output=GetStdHandle(-11),error=GetStdHandle(-12)};
            ProcessInfo process;
            if(!CreateProcess(args[0],"\""+args[0]+"\" /ErrorStdOut \""+args[1]+"\"",IntPtr.Zero,IntPtr.Zero,true,0,IntPtr.Zero,System.IO.Path.GetDirectoryName(args[1]),ref startup,out process)) {Console.Error.WriteLine("CreateProcess failed: "+Marshal.GetLastWin32Error());return 1;}
            try {if(WaitForSingleObject(process.process,12000)!=0){TerminateProcess(process.process,124);return 124;}uint code;GetExitCodeProcess(process.process,out code);return (int)code;}
            finally {CloseHandle(process.thread);CloseHandle(process.process);}
        } finally {CloseDesktop(desktop);}
    }
}
