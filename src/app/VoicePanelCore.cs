using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
public static class VoicePanelCore {
 public sealed class Candidate{public long HWND;public uint PID;public uint ThreadID;public long StartFileTime;}
 [StructLayout(LayoutKind.Sequential)]struct Rect{public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")]static extern bool SetProcessDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")]static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string name);
 [DllImport("user32.dll")]static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("dwmapi.dll")]static extern int DwmGetWindowAttribute(IntPtr h,int a,out int v,int n);
 [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]static extern IntPtr GetThreadDesktop(uint t);
 [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetUserObjectInformation(IntPtr h,int i,StringBuilder s,int n,out int needed);
 static readonly string Windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
 static readonly string ExplorerPath=Path.Combine(Windows,"Explorer.EXE");
 static readonly string TextHostPath=Path.Combine(Windows,"SystemApps","MicrosoftWindows.Client.CBS_cw5n1h2txyewy","TextInputHost.exe");
 static bool ProcessIdentity(int pid,long start,string expected){try{var p=Process.GetProcessById(pid);return p.StartTime.ToUniversalTime().ToFileTimeUtc()==start&&String.Equals(p.MainModule.FileName,expected,StringComparison.OrdinalIgnoreCase);}catch{return false;}}
 static string Class(IntPtr h){var c=new StringBuilder(256);GetClassName(h,c,256);return c.ToString();}
 static bool Live(IntPtr h){int cloak;return IsWindow(h)&&IsWindowVisible(h)&&DwmGetWindowAttribute(h,14,out cloak,4)==0&&cloak==0;}
 static bool FrameIdentity(Candidate c){uint p;uint t=GetWindowThreadProcessId(new IntPtr(c.HWND),out p);return c.HWND!=0&&p==c.PID&&t==c.ThreadID&&Class(new IntPtr(c.HWND))=="ApplicationFrameWindow"&&ProcessIdentity((int)p,c.StartFileTime,ExplorerPath);}
 sealed class Verified{public Candidate Frame;public IntPtr Core;public int PID;public long Start;public AutomationElement Close;}
 static AutomationElement UniqueChild(AutomationElement root,string id){var a=root.FindAll(TreeScope.Children,new PropertyCondition(AutomationElement.AutomationIdProperty,id));return a.Count==1?a[0]:null;}
 static Verified Verify(Candidate frame){if(!FrameIdentity(frame)||!Live(new IntPtr(frame.HWND)))return null;IntPtr core=FindWindowEx(new IntPtr(frame.HWND),IntPtr.Zero,"Windows.UI.Core.CoreWindow",null);if(core==IntPtr.Zero||GetParent(core).ToInt64()!=frame.HWND||!Live(core))return null;uint pid;GetWindowThreadProcessId(core,out pid);long start;try{start=Process.GetProcessById((int)pid).StartTime.ToUniversalTime().ToFileTimeUtc();}catch{return null;}if(!ProcessIdentity((int)pid,start,TextHostPath))return null;var root=AutomationElement.FromHandle(core);if(root.Current.ProcessId!=pid||root.Current.NativeWindowHandle!=core.ToInt64())return null;var panel=UniqueChild(root,"Windows.Shell.InputApp.VoiceTypingUI");if(panel==null||panel.Current.ProcessId!=pid||panel.Current.IsOffscreen)return null;var close=UniqueChild(panel,"CloseButton");var mic=UniqueChild(panel,"FloatyMicrophoneButton");var settings=UniqueChild(panel,"SettingsFlyoutButton");if(close==null||mic==null||settings==null)return null;var c=close.Current;if(c.ProcessId!=pid||c.ControlType!=ControlType.Button||c.IsOffscreen||!c.IsEnabled)return null;object invoke;if(!close.TryGetCurrentPattern(InvokePattern.Pattern,out invoke))return null;Rect bounds;if(!GetWindowRect(core,out bounds))return null;var r=c.BoundingRectangle;if(r.IsEmpty||r.Width<=0||r.Height<=0||r.Left<bounds.Left-2||r.Top<bounds.Top-2||r.Right>bounds.Right+2||r.Bottom>bounds.Bottom+2)return null;if(!FrameIdentity(frame)||!Live(core)||!ProcessIdentity((int)pid,start,TextHostPath))return null;return new Verified{Frame=frame,Core=core,PID=(int)pid,Start=start,Close=close};}
 static bool StillLive(Verified v){return FrameIdentity(v.Frame)&&Live(new IntPtr(v.Frame.HWND))&&Live(v.Core)&&GetParent(v.Core).ToInt64()==v.Frame.HWND&&ProcessIdentity(v.PID,v.Start,TextHostPath);}
 static Dictionary<int,long> Hosts(){var map=new Dictionary<int,long>();foreach(string name in new[]{"Explorer","TextInputHost"})foreach(var p in Process.GetProcessesByName(name)){try{string path=p.MainModule.FileName;if(String.Equals(path,ExplorerPath,StringComparison.OrdinalIgnoreCase)||String.Equals(path,TextHostPath,StringComparison.OrdinalIgnoreCase))map[p.Id]=p.StartTime.ToUniversalTime().ToFileTimeUtc();}catch{}finally{p.Dispose();}}return map;}
 static bool HostsAlive(Dictionary<int,long> map){foreach(var p in map)try{if(Process.GetProcessById(p.Key).StartTime.ToUniversalTime().ToFileTimeUtc()!=p.Value)return false;}catch{return false;}return true;}
 public static string Execute(Candidate[] candidates,Func<bool> active,int sequence){
  var total=Stopwatch.StartNew();string status="rejected",reason="";bool invoked=false,closed=false,hosts=true,other=true;int count=0;long frame=0,core=0;double select=0,reverify=0,invoke=0,wait=0;
  try{if(candidates==null||candidates.Length>16)throw new Exception("candidate_limit");var valid=new List<Verified>();var seen=new HashSet<long>();var sw=Stopwatch.StartNew();foreach(var c in candidates){if(!active())throw new Exception("request_expired");if(!seen.Add(c.HWND))continue;var v=Verify(c);if(v!=null)valid.Add(v);}select=sw.Elapsed.TotalMilliseconds;count=valid.Count;if(count!=1)status=count==0?"no_verified_panel":"ambiguous_panel";else{var v=valid[0];frame=v.Frame.HWND;core=v.Core.ToInt64();sw.Restart();var fresh=Verify(v.Frame);reverify=sw.Elapsed.TotalMilliseconds;if(fresh==null||fresh.Core!=v.Core||fresh.PID!=v.PID||fresh.Start!=v.Start)throw new Exception("changed_before_invoke");var hostMap=Hosts();if(!hostMap.ContainsKey(v.PID)||!hostMap.ContainsKey((int)v.Frame.PID))throw new Exception("host_snapshot_failed");IntPtr fg=GetForegroundWindow();bool another=fg.ToInt64()!=frame&&fg!=v.Core&&IsWindow(fg);if(!active()||!StillLive(fresh))throw new Exception("changed_or_expired_before_invoke");sw.Restart();((InvokePattern)fresh.Close.GetCurrentPattern(InvokePattern.Pattern)).Invoke();invoke=sw.Elapsed.TotalMilliseconds;invoked=true;sw.Restart();DateTime until=DateTime.UtcNow.AddMilliseconds(1200);while(active()&&StillLive(fresh)&&DateTime.UtcNow<until)Thread.Sleep(10);wait=sw.Elapsed.TotalMilliseconds;closed=!StillLive(fresh);hosts=HostsAlive(hostMap);other=!another||IsWindow(fg);status=closed&&hosts&&other?"closed":"close_not_confirmed";}}
  catch(Exception e){reason=e.GetType().Name+":"+e.Message;}
  return new JavaScriptSerializer().Serialize(new{UTC=DateTime.UtcNow.ToString("o"),Seq=sequence,Status=status,Reason=reason,Method="UIA_CloseButton_Invoke",Resident=true,VerifiedCandidates=count,HWND=frame,CoreHWND=core,CloseInvoked=invoked,PanelNoLongerVisible=closed,HostsStillAlive=hosts,NonTargetForegroundStillExists=other,SelectMs=select,ReverifyMs=reverify,InvokeMs=invoke,WaitForHiddenMs=wait,TotalMs=total.Elapsed.TotalMilliseconds,ReadsInputText=false,UsesMicrophone=false,UsesGlobalKeys=false,UsesCoordinateClicks=false,SavesImages=false});
 }
}
