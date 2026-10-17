using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Collections.Generic;
using System.Windows.Forms;

internal static class Installer {
    const string Marker=".win-voice-hotkey-install";
    sealed class StopFailure:Exception {
        public readonly int Code;
        public StopFailure(int code,string message):base(message){Code=code;}
    }
    static string DefaultTarget {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","WinVoiceHotkey");}}
    static void Shortcut(string target,string path) {
        Type type=Type.GetTypeFromProgID("WScript.Shell");object shell=Activator.CreateInstance(type);
        object link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
        var lt=link.GetType();lt.InvokeMember("TargetPath",BindingFlags.SetProperty,null,link,new object[]{target});
        lt.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,link,new object[]{Path.GetDirectoryName(target)});
        lt.InvokeMember("Save",BindingFlags.InvokeMethod,null,link,null);
    }
    static List<string> InstalledFiles(string folder) {
        string manifest=Path.Combine(folder,"install-files.txt");
        if(!File.Exists(manifest))throw new IOException("安装文件清单缺失，未更改安装文件。请恢复完整安装目录后重试。");
        var files=new List<string>();
        foreach(string relative in File.ReadAllLines(manifest)) {
            string file=Path.GetFullPath(Path.Combine(folder,relative));
            if(!file.StartsWith(folder+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("安装文件清单路径无效，未更改安装文件。");
            files.Add(file);
        }
        return files;
    }
    static void StopBeforeChangingFiles(string folder) {
        const string retry="未继续覆盖或删除安装文件。请先从托盘退出 Win Voice Hotkey，确认已退出后重试；如提示状态校验失败，请先启动完整旧版以刷新状态，再退出后重试。不要直接删除运行中的程序文件。";
        int code;
        try {
            // Never trust the old launcher's exit code: v0.1.1 can report zero while still running.
            // Compile the fixed launcher's retained-handle/token verification into this installer too.
            code=Launcher.StopAndConfirm(Launcher.Data(folder));
        } catch(Exception error){throw new StopFailure(2,"无法完成停止检查："+error.Message+"。"+retry);}
        if(code!=0)throw new StopFailure(code==3?3:2,
            (code==3?"旧实例退出超时。":"旧实例校验或停止失败（退出码 "+code+"）。")+retry);
    }
    static void Install(string folder,bool isolated) {
        folder=Path.GetFullPath(folder);
        bool upgrade=File.Exists(Path.Combine(folder,Marker));
        if(Directory.Exists(folder)&&Directory.GetFileSystemEntries(folder).Length!=0&&!upgrade)
            throw new IOException("目标目录非空且不是可识别的安装目录，请选择空目录；未覆盖现有文件。");
        var oldFiles=upgrade?InstalledFiles(folder):new List<string>();
        var owned=new HashSet<string>(oldFiles,StringComparer.OrdinalIgnoreCase);
        var installed=new List<string>();
        using(var resource=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
            if(resource==null)throw new InvalidOperationException("Installer payload is missing.");
            using(var zip=new ZipArchive(resource,ZipArchiveMode.Read)) {
                // Validate all destinations before stopping or changing an existing installation.
                foreach(var entry in zip.Entries) {
                    string file=Path.GetFullPath(Path.Combine(folder,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                    if(!file.StartsWith(folder+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid package path.");
                    if(!entry.FullName.EndsWith("/")&&File.Exists(file)&&!owned.Contains(file))
                        throw new IOException("新版本文件与未归属本程序的现有文件冲突，未覆盖："+entry.FullName);
                }
                foreach(string reserved in new[]{"Uninstall.exe",Marker})
                    if(File.Exists(Path.Combine(folder,reserved))&&!owned.Contains(Path.Combine(folder,reserved)))
                        throw new IOException("安装目录中的文件归属不明确，未覆盖："+reserved);
                if(upgrade)StopBeforeChangingFiles(folder);
                Directory.CreateDirectory(folder);
                foreach(var entry in zip.Entries) {
                    string file=Path.GetFullPath(Path.Combine(folder,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                    if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(file);continue;}
                    Directory.CreateDirectory(Path.GetDirectoryName(file));entry.ExtractToFile(file,upgrade);installed.Add(entry.FullName);
                }
            }
        }
        File.Delete(Path.Combine(folder,"portable.flag"));
        File.WriteAllText(Path.Combine(folder,Marker),"WinVoiceHotkey 0.1.2\n");
        File.Copy(Assembly.GetExecutingAssembly().Location,Path.Combine(folder,"Uninstall.exe"),upgrade);
        installed.Add("Uninstall.exe");installed.Add(Marker);
        File.WriteAllLines(Path.Combine(folder,"install-files.txt"),installed.ToArray());
        var retained=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string relative in installed)retained.Add(Path.GetFullPath(Path.Combine(folder,relative)));
        foreach(string file in oldFiles)if(!retained.Contains(file)&&File.Exists(file))File.Delete(file);
        if(!isolated) {
            string menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"Win Voice Hotkey");Directory.CreateDirectory(menu);
            Shortcut(Path.Combine(folder,"WinVoiceHotkey.exe"),Path.Combine(menu,"Win Voice Hotkey.lnk"));
            Shortcut(Path.Combine(folder,"Uninstall.exe"),Path.Combine(menu,"Uninstall.lnk"));
        }
    }
    static void Uninstall(string folder,bool isolated) {
        folder=Path.GetFullPath(folder);
        if(!File.Exists(Path.Combine(folder,Marker)))throw new IOException("安装标记缺失，未删除任何目录。");
        var files=InstalledFiles(folder);
        StopBeforeChangingFiles(folder);
        if(!isolated) {
            string startup=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"WinVoiceHotkey.lnk");if(File.Exists(startup))File.Delete(startup);
            string menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"Win Voice Hotkey");
            foreach(string name in new[]{"Win Voice Hotkey.lnk","Uninstall.lnk"}){string link=Path.Combine(menu,name);if(File.Exists(link))File.Delete(link);}
            if(Directory.Exists(menu)&&Directory.GetFileSystemEntries(menu).Length==0)Directory.Delete(menu);
        }
        string self=Assembly.GetExecutingAssembly().Location;
        string manifest=Path.Combine(folder,"install-files.txt");
        foreach(string file in files)if(!String.Equals(file,self,StringComparison.OrdinalIgnoreCase)&&File.Exists(file))File.Delete(file);
        File.Delete(manifest);
        var directories=Directory.GetDirectories(folder,"*",SearchOption.AllDirectories);
        Array.Sort(directories,(a,b)=>b.Length.CompareTo(a.Length));
        foreach(string dir in directories)if(Directory.GetFileSystemEntries(dir).Length==0)Directory.Delete(dir);
        // A running Uninstall.exe stays as an inert file; no self-delete helper is used.
    }
    [STAThread] static int Main(string[] args) {
        bool silent=Array.IndexOf(args,"--silent")>=0,isolated=Array.IndexOf(args,"--isolated")>=0;
        bool uninstall=Path.GetFileName(Assembly.GetExecutingAssembly().Location).Equals("Uninstall.exe",StringComparison.OrdinalIgnoreCase)||Array.IndexOf(args,"--uninstall")>=0;
        string target=uninstall?AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar):DefaultTarget;
        for(int i=0;i<args.Length-1;i++)if(args[i]=="--target")target=args[i+1];
        try {
            if(!silent&&MessageBox.Show(uninstall?"卸载 Win Voice Hotkey，保留用户配置？":"安装或升级 Win Voice Hotkey 到以下目录？\n\n"+target,"Win Voice Hotkey",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return 0;
            if(uninstall)Uninstall(target,isolated);else Install(target,isolated);
            if(!silent)MessageBox.Show(uninstall?"卸载完成，用户配置已保留。关闭后可删除剩余的安装目录。":"安装或升级完成。请启动 Win Voice Hotkey。","Win Voice Hotkey");
            return 0;
        } catch(Exception error) {
            if(!silent)MessageBox.Show(error.Message,"Win Voice Hotkey",MessageBoxButtons.OK,MessageBoxIcon.Error);else Launcher.WriteError(error.Message);
            return error is StopFailure?((StopFailure)error).Code:1;
        }
    }
}
