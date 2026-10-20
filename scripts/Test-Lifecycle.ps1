[CmdletBinding()]
param()
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$package=Join-Path $root 'out\package'
if(-not(Test-Path -LiteralPath $package)){throw 'Build first.'}
$run=Join-Path $root ('out\lifecycle-'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $run 'fixture install with spaces'
$app=Join-Path $fixture 'app'
New-Item -ItemType Directory -Path (Join-Path $app 'dependencies')|Out-Null
Copy-Item -LiteralPath (Join-Path $package 'WinVoiceHotkey.exe') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $package 'app\dependencies\AutoHotkey64.exe') -Destination (Join-Path $app 'dependencies')
Copy-Item -LiteralPath (Join-Path $root 'src\app\RuntimeState.ahk') -Destination $app
# The no-input fixture uses a distinct test mutex, never the daily application's mutex.
$paths=[IO.File]::ReadAllText((Join-Path $root 'src\app\AppPaths.ahk'))
$paths=$paths.Replace('Local\WinVoiceHotkey.App',('Local\WinVoiceHotkey.Test.'+[guid]::NewGuid().ToString('N')))
[IO.File]::WriteAllText((Join-Path $app 'AppPaths.ahk'),$paths,[Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath (Join-Path $root 'tests\fixtures\LifecycleNoInput.ahk') -Destination (Join-Path $app 'WinHGate.ahk')
$exe=Join-Path $fixture 'WinVoiceHotkey.exe'
$dataDirectory=Join-Path $run 'fixture profile'
New-Item -ItemType Directory -Path $dataDirectory|Out-Null
$config=Join-Path $dataDirectory 'config.ini'
[IO.File]::WriteAllText($config,"[Mapping]`r`nEnabled=1`r`nKey=XButton1`r`nCloseKey=XButton1`r`n",[Text.Encoding]::Unicode)
$configHash=(Get-FileHash -LiteralPath $config).Hash
$results=[Collections.Generic.List[object]]::new()
function Check($name,$pass,$details){$r=[ordered]@{Name=$name;Passed=[bool]$pass;Details=$details};$results.Add($r);$r|ConvertTo-Json -Depth 5 -Compress|Add-Content -LiteralPath (Join-Path $run 'lifecycle-checks.jsonl') -Encoding utf8;if(-not $pass){throw $name}}
function State { $s=@{};$section='';foreach($line in [IO.File]::ReadAllLines((Join-Path $dataDirectory 'mapping-state.ini'))){if($line.StartsWith('[')){$section=$line;continue};if($section -eq '[State]' -and $line -match '^([^=]+)=(.*)$'){$s[$Matches[1]]=$Matches[2]}};return $s }
function InvokeFixtureCommand($argument){$i=[Diagnostics.ProcessStartInfo]::new($exe,$argument);$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.EnvironmentVariables['WIN_VOICE_HOTKEY_DATA_DIR']=$dataDirectory;$i.EnvironmentVariables.Remove('WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS');$p=[Diagnostics.Process]::Start($i);$null=$p.Handle;if(-not $p.WaitForExit(12000)){throw 'Fixture launcher timed out'};$outTask=$p.StandardOutput.ReadToEndAsync();$errorTask=$p.StandardError.ReadToEndAsync();if(-not $outTask.Wait(2500) -or -not $errorTask.Wait(2500)){throw 'Resident child retained caller output pipe'};return @{Code=$p.ExitCode;Stdout=$outTask.Result;Stderr=$errorTask.Result} }
Add-Type -TypeDefinition @"
using System;using System.Text;using System.Runtime.InteropServices;
public static class DetachedVoiceFixture {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct SI {public int cb;public string reserved,desktop,title;public int x,y,w,h,xc,yc,fill,flags;public short show,cb2;public IntPtr reserved2,input,output,error;}
 [StructLayout(LayoutKind.Sequential)]struct PI {public IntPtr process,thread;public uint pid,tid;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string app,StringBuilder command,IntPtr sa,IntPtr ta,bool inherit,uint flags,IntPtr env,string dir,ref SI si,out PI pi);
 [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr p,uint ms);
 [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr p,out uint code);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr p);
 public static int Run(string file,string directory){var si=new SI{cb=Marshal.SizeOf(typeof(SI)),flags=0x100,input=IntPtr.Zero,output=IntPtr.Zero,error=IntPtr.Zero};PI pi;if(!CreateProcess(file,new StringBuilder("\""+file+"\""),IntPtr.Zero,IntPtr.Zero,false,8,IntPtr.Zero,directory,ref si,out pi))throw new Exception("Detached create failed "+Marshal.GetLastWin32Error());try{if(WaitForSingleObject(pi.process,12000)!=0)throw new Exception("Detached wait timeout");uint code;GetExitCodeProcess(pi.process,out code);return (int)code;}finally{CloseHandle(pi.thread);CloseHandle(pi.process);}}
}
"@
$oldData=[Environment]::GetEnvironmentVariable('WIN_VOICE_HOTKEY_DATA_DIR')
$oldSupport=[Environment]::GetEnvironmentVariable('WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS')
try{
 [Environment]::SetEnvironmentVariable('WIN_VOICE_HOTKEY_DATA_DIR',$dataDirectory,'Process')
 [Environment]::SetEnvironmentVariable('WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS',$null,'Process')
 $code=[DetachedVoiceFixture]::Run($exe,$env:WINDIR)
 $s=State
 Check 'detached no-console/no-stdio startup verifies ready' ($code -eq 0 -and $s.Running -eq '1' -and $s.Ready -eq '1' -and $s.Phase -eq 'ready') @{Exit=$code;State=$s}
 $firstPID=$s.PID;$firstToken=$s.InstanceToken
 $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$firstPID)
 Check 'snapshot belongs to actual fixture process' ($p -and $p.ExecutablePath -eq (Join-Path $fixture 'app\dependencies\AutoHotkey64.exe')) @{PID=$firstPID;Path=$p.ExecutablePath}
 $r=InvokeFixtureCommand '';$s=State
 Check 'duplicate start keeps same process and token' ($r.Code -eq 0 -and $s.PID -eq $firstPID -and $s.InstanceToken -eq $firstToken) $r
 $statePath=Join-Path $dataDirectory 'mapping-state.ini';$saved=[IO.File]::ReadAllBytes($statePath)
 $text=[IO.File]::ReadAllText($statePath);[IO.File]::WriteAllText($statePath,([regex]::Replace($text,'(?m)^InstanceToken=\d+','InstanceToken=0')),[Text.Encoding]::Unicode)
 $r=InvokeFixtureCommand '--stop'
 Check 'invalid token rejected without stopping live process' ($r.Code -eq 2 -and $null -ne (Get-Process -Id ([int]$firstPID) -ErrorAction SilentlyContinue)) $r
 [IO.File]::WriteAllBytes($statePath,$saved)
 $text=[IO.File]::ReadAllText($statePath);[IO.File]::WriteAllText($statePath,([regex]::Replace($text,'(?m)^PID=\d+','PID=9999999')),[Text.Encoding]::Unicode)
 $r=InvokeFixtureCommand '--stop';$s=State
 Check 'stale recorded PID discovers and normally stops true owner' ($r.Code -eq 0 -and $null -eq (Get-Process -Id ([int]$firstPID) -ErrorAction SilentlyContinue)) $r
 Check 'normal exit publishes current PID and no ready/running flag' ($s.PID -eq $firstPID -and $s.Running -eq '0' -and $s.Ready -eq '0' -and $s.Phase -eq 'stopped') $s
 $r=InvokeFixtureCommand '--stop';Check 'already exited no-op is accurate' ($r.Code -eq 0) $r
 $failFlag=Join-Path $fixture 'app\fail-start.fixture';[IO.File]::WriteAllText($failFlag,'Synthetic startup failure fixture')
 $r=InvokeFixtureCommand '';$s=State
 Check 'startup failure returns nonzero and never ready' ($r.Code -ne 0 -and $s.Running -eq '0' -and $s.Ready -eq '0' -and $s.Phase -eq 'failed') @{Result=$r;State=$s}
 Remove-Item -LiteralPath $failFlag
 $r=InvokeFixtureCommand '';$s=State
 Check 'next successful start replaces failure record' ($r.Code -eq 0 -and $s.Running -eq '1' -and $s.Ready -eq '1' -and $s.PID -ne $firstPID) @{Result=$r;State=$s}
 $r=InvokeFixtureCommand '--stop';Check 'final normal fixture stop' ($r.Code -eq 0) $r
 $log=Get-Content -LiteralPath (Join-Path $dataDirectory 'lifecycle.log') -Raw
 Check 'lifecycle records exist with support logging disabled' ($log -match 'event=starting' -and $log -match 'event=stopped' -and $log -match 'event=failed') @{Log=$log}
 Check 'user-selected test bindings untouched across all transitions' ((Get-FileHash -LiteralPath $config).Hash -eq $configHash) @{SHA256=$configHash}
 $remaining=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -like ($fixture+'\*')})
 Check 'no fixture process left' ($remaining.Count -eq 0) $remaining
 $summary=[ordered]@{Passed=$results.Count;AllPassed=$true;NoHooks=$true;NoVoice=$true;NoMicrophone=$true;NoActualLoginOrReboot=$true;DetachedEnvironment='Same user/session, absent standard handles, different current directory, diagnostic flag absent';Cases=$results}
 $summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $run 'lifecycle-regression.json') -Encoding utf8
 [pscustomobject]@{Passed=$results.Count;AllPassed=$true;NoHooks=$true;NoVoice=$true}|ConvertTo-Json
}finally{
 [Environment]::SetEnvironmentVariable('WIN_VOICE_HOTKEY_DATA_DIR',$oldData,'Process')
 [Environment]::SetEnvironmentVariable('WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS',$oldSupport,'Process')
}