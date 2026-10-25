[CmdletBinding()]
param([string]$ArtifactDirectory,[string]$Label)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$ArtifactDirectory){$ArtifactDirectory=Join-Path $root 'out'}
if(!$Label){$Label='packages-'+[guid]::NewGuid().ToString('N')}
$run=Join-Path (Join-Path $root 'out') $Label
if(Test-Path -LiteralPath $run){throw 'Retain earlier evidence; choose a fresh label.'}
New-Item -ItemType Directory -Path $run|Out-Null
$setup=Get-Item -LiteralPath (Join-Path $ArtifactDirectory 'win-voice-hotkey-0.1.4-windows-x64-setup.exe')
$zip=Get-Item -LiteralPath (Join-Path $ArtifactDirectory 'win-voice-hotkey-0.1.4-windows-x64-portable.zip')
$install=Join-Path $run 'isolated install with spaces'
$profile=Join-Path $run 'isolated profile'
New-Item -ItemType Directory -Path $profile|Out-Null
$steps=[Collections.Generic.List[object]]::new()
function InvokeFinite([string]$file,[string]$arguments,[string]$data) {
 $i=[Diagnostics.ProcessStartInfo]::new($file,$arguments);$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $i.EnvironmentVariables['WIN_VOICE_HOTKEY_DATA_DIR']=$data;$i.EnvironmentVariables.Remove('WIN_VOICE_HOTKEY_SUPPORT_DIAGNOSTICS')
 $p=[Diagnostics.Process]::Start($i);$null=$p.Handle
 try {if(-not $p.WaitForExit(25000)){throw 'Only isolated package test process exceeded its deadline.'};$o=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();if(-not $o.Wait(2500)-or -not $err.Wait(2500)){throw 'Package caller pipe remained open'};$r=[ordered]@{File=[IO.Path]::GetFileName($file);Arguments=$arguments;Exit=$p.ExitCode;Stdout=$o.Result;Stderr=$err.Result};$steps.Add($r);$r|ConvertTo-Json -Depth 5 -Compress|Add-Content -LiteralPath (Join-Path $run 'steps.jsonl') -Encoding UTF8;if($p.ExitCode -ne 0){throw ('Package test failed: '+$err.Result)}}finally{$p.Dispose()}
}
function Smoke([string]$root,[string]$data){$exe=Join-Path $root 'WinVoiceHotkey.exe';InvokeFinite $exe '--smoke-test' $data;$smoke=Get-Content -LiteralPath (Join-Path $data 'smoke-results.json') -Raw|ConvertFrom-Json;$state=[IO.File]::ReadAllText((Join-Path $data 'mapping-state.ini'));if(-not $smoke.broker_ready -or $smoke.hooks_installed -or $smoke.microphone_used -or $state -notmatch 'Version=0.1.4' -or $state -notmatch 'Phase=stopped' -or $state -notmatch 'Ready=0'){throw 'Smoke result or final version/state incorrect'};return $smoke}
InvokeFinite $setup.FullName ('--silent --isolated --target "'+$install+'"') $profile
$installedSmoke=Smoke $install $profile
$config=Join-Path $profile 'config.ini';$configHash=(Get-FileHash -LiteralPath $config).Hash;$configText=[IO.File]::ReadAllText($config)
if($configText -notmatch '(?m)^Key=XButton1\r?$' -or $configText -notmatch '(?m)^CloseKey=XButton2\r?$'){throw 'Fresh defaults incorrect'}
$unrelated=Join-Path $install 'unrelated.keep';[IO.File]::WriteAllText($unrelated,'synthetic unrelated file')
InvokeFinite $setup.FullName ('--silent --isolated --target "'+$install+'"') $profile
if((Get-FileHash -LiteralPath $config).Hash -ne $configHash -or -not(Test-Path -LiteralPath $unrelated)){throw 'Upgrade did not preserve data'}
InvokeFinite $setup.FullName ('--silent --isolated --uninstall --target "'+$install+'"') $profile
if((Get-FileHash -LiteralPath $config).Hash -ne $configHash -or -not(Test-Path -LiteralPath $unrelated) -or (Test-Path -LiteralPath (Join-Path $install 'app\dependencies\AutoHotkey64.exe'))){throw 'Uninstall retention/removal incorrect'}
$portable=Join-Path $run 'portable with spaces';Expand-Archive -LiteralPath $zip.FullName -DestinationPath $portable
$portableProfile=Join-Path $portable 'data';New-Item -ItemType Directory -Path $portableProfile|Out-Null
$portableSmoke=Smoke $portable $portableProfile
$r=[ordered]@{AllPassed=$true;InstalledSmoke=$installedSmoke;PortableSmoke=$portableSmoke;IsolatedInstallUpgradeUninstall=$true;DefaultOpen='XButton1';DefaultClose='XButton2';ConfigPreserved=$true;UnrelatedPreserved=$true;NoGlobalHooks=$true;NoVoiceOrMicrophone=$true;PackageSmokeDesktop='Default (required by real broker); no hooks or input';Steps=$steps}
$r|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $run 'package-validation.json') -Encoding UTF8
[pscustomobject]@{AllPassed=$true;Label=$Label;InstalledAndPortableSmoke=$true;InstallUpgradeUninstall=$true}|ConvertTo-Json