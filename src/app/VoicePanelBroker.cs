using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;
public static class VoicePanelBroker{
 [StructLayout(LayoutKind.Sequential)]struct CopyData{public IntPtr Token;public int Length;public IntPtr Data;}
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]static extern bool SetProcessDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr GetProp(IntPtr h,string name);
 [DllImport("user32.dll")]static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]static extern IntPtr GetThreadDesktop(uint t);
 [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetUserObjectInformation(IntPtr h,int i,StringBuilder s,int n,out int needed);
 public sealed class Envelope{public int Seq;public VoicePanelCore.Candidate[] Candidates;}
 sealed class Context{public Envelope Request;public DateTime Deadline;public volatile bool Cancelled;public int Done;}
 static IntPtr Owner;static int OwnerPID;static long OwnerStart;static int Token;static string Session,Folder,ReadyPath;static BlockingCollection<Context> Queue=new BlockingCollection<Context>(1);static Context Current;static object Gate=new object();static volatile bool Exiting;static bool Warmed;static double WarmMs;static BrokerWindow Window;
 static bool OwnerAlive(){uint p;GetWindowThreadProcessId(Owner,out p);if(p!=OwnerPID||GetProp(Owner,"WinVoiceHotkeyBrokerOwner").ToInt64()!=Token)return false;try{return Process.GetProcessById(OwnerPID).StartTime.ToUniversalTime().Ticks==OwnerStart;}catch{return false;}}
 static int Code(string status){switch(status){case "closed":return 1;case "no_verified_panel":return 2;case "ambiguous_panel":return 3;case "close_not_confirmed":return 4;case "timeout":return 6;default:return 5;}}
 static void Complete(Context ctx,string json){if(Interlocked.Exchange(ref ctx.Done,1)!=0)return;try{var d=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,object>>(json);int code=Code((string)d["Status"]);if(OwnerAlive())PostMessage(Owner,0x805A,new IntPtr(((long)ctx.Request.Seq<<8)|((uint)code)),new IntPtr(Token));}catch{}lock(Gate){if(Current==ctx)Current=null;}}
 static string Failure(int seq,string status,string reason){return new JavaScriptSerializer().Serialize(new{UTC=DateTime.UtcNow.ToString("o"),Seq=seq,Status=status,Reason=reason,Method="UIA_CloseButton_Invoke",Resident=true,CloseInvoked=false,ReadsInputText=false,UsesMicrophone=false});}
 static void Worker(){var sw=Stopwatch.StartNew();try{int pid=AutomationElement.RootElement.Current.ProcessId;Warmed=pid>=0;}catch{}WarmMs=sw.Elapsed.TotalMilliseconds;try{foreach(var ctx in Queue.GetConsumingEnumerable()){if(Exiting)break;string json=VoicePanelCore.Execute(ctx.Request.Candidates,()=>!ctx.Cancelled&&!Exiting&&OwnerAlive()&&DateTime.UtcNow<ctx.Deadline,ctx.Request.Seq);Complete(ctx,json);}}catch{}}
 sealed class BrokerWindow:NativeWindow,IDisposable{
  public BrokerWindow(){CreateHandle(new CreateParams{Caption="WinVoiceHotkeyBroker",Parent=new IntPtr(-3)});}
  protected override void WndProc(ref Message m){if(m.Msg==0x4A){m.Result=IntPtr.Zero;if(m.WParam!=Owner||!OwnerAlive())return;try{var c=(CopyData)Marshal.PtrToStructure(m.LParam,typeof(CopyData));if(c.Token.ToInt64()!=Token||c.Length<2||c.Length>65536||c.Data==IntPtr.Zero)return;var bytes=new byte[c.Length];Marshal.Copy(c.Data,bytes,0,bytes.Length);var e=new JavaScriptSerializer().Deserialize<Envelope>(Encoding.UTF8.GetString(bytes).TrimEnd('\0'));if(e==null||e.Seq<1||e.Candidates==null||e.Candidates.Length>16)return;Context ctx;lock(Gate){if(Current!=null){m.Result=new IntPtr(2);return;}ctx=new Context{Request=e,Deadline=DateTime.UtcNow.AddSeconds(2)};Current=ctx;}if(!Queue.TryAdd(ctx)){lock(Gate){Current=null;}return;}m.Result=new IntPtr(1);return;}catch{return;}}
   if(m.Msg==0x9001&&m.WParam==Owner&&m.LParam.ToInt64()==Token){Application.ExitThread();return;}base.WndProc(ref m);}
  public void Dispose(){DestroyHandle();}
 }
 [STAThread]public static int Main(string[] args){if(args.Length!=5||args[0]!="--broker")return 64;Guid id;if(!Guid.TryParse(args[1],out id))return 64;SetProcessDpiAwarenessContext(new IntPtr(-4));Session=id.ToString();OwnerPID=int.Parse(args[2]);Owner=new IntPtr(long.Parse(args[3]));Token=int.Parse(args[4]);Folder=Environment.GetEnvironmentVariable("WIN_VOICE_HOTKEY_DATA_DIR");if(String.IsNullOrEmpty(Folder))return 64;ReadyPath=Path.Combine(Folder,"close-broker-"+Session+".ready.json");try{OwnerStart=Process.GetProcessById(OwnerPID).StartTime.ToUniversalTime().Ticks;}catch{return 4;}if(!OwnerAlive())return 4;var desktop=new StringBuilder(256);int needed;if(!GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()),2,desktop,512,out needed)||desktop.ToString()!="Default")return 4;var worker=new Thread(Worker){IsBackground=true};worker.SetApartmentState(ApartmentState.MTA);worker.Start();DateTime readyUntil=DateTime.UtcNow.AddSeconds(2);while(!Warmed&&WarmMs==0&&DateTime.UtcNow<readyUntil)Thread.Sleep(5);Window=new BrokerWindow();var timer=new System.Windows.Forms.Timer{Interval=100};timer.Tick+=(s,e)=>{if(!OwnerAlive()){Application.ExitThread();return;}Context c;lock(Gate)c=Current;if(c!=null&&DateTime.UtcNow>=c.Deadline){c.Cancelled=true;Complete(c,Failure(c.Request.Seq,"timeout","bounded_uia_timeout"));Exiting=true;Application.ExitThread();}};timer.Start();File.WriteAllText(ReadyPath,new JavaScriptSerializer().Serialize(new{PID=Process.GetCurrentProcess().Id,HWND=Window.Handle.ToInt64(),OwnerPID=OwnerPID,Token=Token,Warmed=Warmed,WarmMs=WarmMs,Ready=true}));try{Application.Run();}finally{Exiting=true;Context c;lock(Gate)c=Current;if(c!=null)c.Cancelled=true;Queue.CompleteAdding();timer.Dispose();Window.Dispose();try{File.Delete(ReadyPath);}catch{}}return 0;}
}
