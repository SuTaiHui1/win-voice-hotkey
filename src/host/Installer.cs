using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Collections.Generic;
using System.Threading;
using System.Windows.Forms;

internal static class Installer {
    const string Marker=".win-voice-hotkey-install";
    static string DefaultTarget {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","WinVoiceHotkey");}}
    static void Shortcut(string target,string path) {
        Type type=Type.GetTypeFromProgID("WScript.Shell");object shell=Activator.CreateInstance(type);
        object link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
        var lt=link.GetType();lt.InvokeMember("TargetPath",BindingFlags.SetProperty,null,link,new object[]{target});
        lt.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,link,new object[]{Path.GetDirectoryName(target)});
        lt.InvokeMember("Save",BindingFlags.InvokeMethod,null,link,null);
    }
    static void Install(string folder,bool isolated) {
        folder=Path.GetFullPath(folder);
        if(Directory.Exists(folder)&&Directory.GetFileSystemEntries(folder).Length!=0)throw new IOException("目标目录非空；请先卸载旧版，或选择空目录。 / Destination must be empty.");
        Directory.CreateDirectory(folder);
        var installed=new List<string>();
        using(var resource=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
            if(resource==null)throw new InvalidOperationException("Installer payload is missing.");
            using(var zip=new ZipArchive(resource,ZipArchiveMode.Read))foreach(var entry in zip.Entries) {
                string file=Path.GetFullPath(Path.Combine(folder,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                if(!file.StartsWith(folder+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid package path.");
                if(entry.FullName.EndsWith("/")) {Directory.CreateDirectory(file);continue;}
                Directory.CreateDirectory(Path.GetDirectoryName(file));entry.ExtractToFile(file,false);installed.Add(entry.FullName);
            }
        }
        File.Delete(Path.Combine(folder,"portable.flag"));
        File.WriteAllText(Path.Combine(folder,Marker),"WinVoiceHotkey 0.1.1\n");
        File.Copy(Assembly.GetExecutingAssembly().Location,Path.Combine(folder,"Uninstall.exe"));
        installed.Add("Uninstall.exe");installed.Add(Marker);
        File.WriteAllLines(Path.Combine(folder,"install-files.txt"),installed.ToArray());
        if(!isolated) {
            string menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"Win Voice Hotkey");Directory.CreateDirectory(menu);
            Shortcut(Path.Combine(folder,"WinVoiceHotkey.exe"),Path.Combine(menu,"Win Voice Hotkey.lnk"));
            Shortcut(Path.Combine(folder,"Uninstall.exe"),Path.Combine(menu,"Uninstall.lnk"));
        }
    }
    static void Uninstall(string folder,bool isolated) {
        folder=Path.GetFullPath(folder);
        if(!File.Exists(Path.Combine(folder,Marker)))throw new IOException("安装标记缺失，未删除任何目录。 / Installation marker is missing.");
        string launcher=Path.Combine(folder,"WinVoiceHotkey.exe");
        if(File.Exists(launcher))using(var process=Process.Start(new ProcessStartInfo(launcher,"--stop"){UseShellExecute=false,CreateNoWindow=true})){process.WaitForExit(3000);}
        Thread.Sleep(600);
        if(!isolated) {
            string startup=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"WinVoiceHotkey.lnk");if(File.Exists(startup))File.Delete(startup);
            string menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"Win Voice Hotkey");
            foreach(string name in new[]{"Win Voice Hotkey.lnk","Uninstall.lnk"}) {string link=Path.Combine(menu,name);if(File.Exists(link))File.Delete(link);}
            if(Directory.Exists(menu)&&Directory.GetFileSystemEntries(menu).Length==0)Directory.Delete(menu);
        }
        string self=Assembly.GetExecutingAssembly().Location;
        string manifest=Path.Combine(folder,"install-files.txt");
        if(!File.Exists(manifest))throw new IOException("安装文件清单缺失，未删除程序文件。 / Installation manifest is missing.");
        var files=new List<string>();
        foreach(string relative in File.ReadAllLines(manifest)) {
            string file=Path.GetFullPath(Path.Combine(folder,relative));
            if(!file.StartsWith(folder+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid uninstall path.");
            files.Add(file);
        }
        foreach(string file in files)if(!String.Equals(file,self,StringComparison.OrdinalIgnoreCase)&&File.Exists(file))File.Delete(file);
        File.Delete(manifest);
        var directories=Directory.GetDirectories(folder,"*",SearchOption.AllDirectories);
        Array.Sort(directories,(a,b)=>b.Length.CompareTo(a.Length));
        foreach(string dir in directories)if(Directory.GetFileSystemEntries(dir).Length==0)Directory.Delete(dir);
        // Uninstall.exe remains as a small inert file because a running executable
        // cannot delete itself. The user can delete this folder after exit.
    }
    [STAThread] static int Main(string[] args) {
        bool silent=Array.IndexOf(args,"--silent")>=0,isolated=Array.IndexOf(args,"--isolated")>=0;
        bool uninstall=Path.GetFileName(Assembly.GetExecutingAssembly().Location).Equals("Uninstall.exe",StringComparison.OrdinalIgnoreCase)||Array.IndexOf(args,"--uninstall")>=0;
        string target=uninstall?AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar):DefaultTarget;
        for(int i=0;i<args.Length-1;i++)if(args[i]=="--target")target=args[i+1];
        try {
            if(!silent&&MessageBox.Show(uninstall?"卸载 Win Voice Hotkey？保留个人配置。":"安装 Win Voice Hotkey 到当前用户目录？不需要管理员权限，不自动启用自启。\n\n"+target,"Win Voice Hotkey",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return 0;
            if(uninstall)Uninstall(target,isolated);else Install(target,isolated);
            if(!silent)MessageBox.Show(uninstall?"卸载完成。个人配置已保留；关闭后可删除剩余的安装目录。":"安装完成。请从开始菜单启动 Win Voice Hotkey。","Win Voice Hotkey");
            return 0;
        } catch(Exception error) {if(!silent)MessageBox.Show(error.Message,"Win Voice Hotkey",MessageBoxButtons.OK,MessageBoxIcon.Error);else Console.Error.WriteLine(error.Message);return 1;}
    }
}
