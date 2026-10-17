[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SetupExe,
    [Parameter(Mandatory=$true)][string]$OldAppPathsFixture,
    [Parameter(Mandatory=$true)][string]$LegacyLauncherFixture,
    [Parameter(Mandatory=$true)][string]$ResultsPath
)
$ErrorActionPreference='Stop'
if($env:USERNAME -ne 'WDAGUtilityAccount'){throw 'Run only in Windows Sandbox; normal-mode guest hooks are installed.'}
$testRoot=Join-Path $env:TEMP ('WinVoiceHotkeyInstallerStop-'+[guid]::NewGuid().ToString('N'))
$resultsDir=Split-Path ([IO.Path]::GetFullPath($ResultsPath)) -Parent
New-Item -ItemType Directory -Force -Path $testRoot,$resultsDir|Out-Null
$records=New-Object Collections.Generic.List[object]
$oldData=$env:WIN_VOICE_HOTKEY_DATA_DIR
$current=$null;$failure=$null;$complete=$false
function Record($name,$value){$item=@{Name=$name;Utc=[DateTime]::UtcNow.ToString('o');Value=$value};$records.Add($item);$item|ConvertTo-Json -Depth 8 -Compress|Add-Content -Encoding utf8 -LiteralPath (Join-Path $resultsDir 'checks.jsonl')}
function Assert($name,[bool]$ok,$details){Record $name @{Passed=$ok;Details=$details};if(!$ok){throw ('Installer stop regression failed: '+$name)}}
function Run($file,$arguments,$label,[bool]$capture=$true){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$file;$info.Arguments=$arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardError=$capture
    if($capture){$info.StandardErrorEncoding=[Text.Encoding]::UTF8}
    $p=[Diagnostics.Process]::Start($info);$null=$p.Handle
    try{
        if(!$p.WaitForExit(15000)){throw ('Command timeout: '+$label)}
        $errorText=if($capture){$p.StandardError.ReadToEnd()}else{''}
        $r=@{ExitCode=$p.ExitCode;StandardError=$errorText;PID=$p.Id}
        Record $label $r
        return $r
    }finally{$p.Dispose()}
}
function State($path){$s=@{};if(Test-Path -LiteralPath $path){foreach($line in [IO.File]::ReadAllLines($path)){if($line -match '^([^=\[]+)=(.*)$'){$s[$Matches[1]]=$Matches[2]}}};return $s}
function Alive($s){return @(Get-Process -Id ([int]$s['PID']),([int]$s['CloseBrokerPID']) -ErrorAction SilentlyContinue).Count}
function StartInstance($launcher,$profile,$label){
    $r=Run $launcher '' ($label+' launch') $false
    Assert ($label+' launcher success') ($r.ExitCode -eq 0) $r
    $path=Join-Path $profile 'mapping-state.ini';$deadline=[DateTime]::UtcNow.AddSeconds(8)
    do{$s=State $path;if($s['Running'] -eq '1' -and $s['CloseBrokerReady'] -eq '1'){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    $p=if($s['PID']){Get-CimInstance Win32_Process -Filter ('ProcessId='+$s['PID'])}else{$null}
    Assert ($label+' runtime ready') ($s['Running'] -eq '1' -and $s['CloseBrokerReady'] -eq '1' -and $p -and $p.ExecutablePath.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)) $s
    return $s
}
function Snapshot($folder){
    return ((Get-ChildItem -LiteralPath $folder -Recurse -Force|Sort-Object FullName|ForEach-Object {
        $name=$_.FullName.Substring($folder.Length).Replace('\','/')
        if($_.PSIsContainer){'D '+$name}else{'F '+$name+' '+(Get-FileHash -LiteralPath $_.FullName).Hash}
    }) -join "`n")
}
try{
    Assert 'no preexisting guest project process' (@(Get-Process -Name WinVoiceHotkey,AutoHotkey64,VoicePanelBroker -ErrorAction SilentlyContinue).Count -eq 0) $env:COMPUTERNAME
    $legacyLauncher=Join-Path $testRoot 'LegacyLauncher.exe'
    $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $csc /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll ('/out:'+$legacyLauncher) $LegacyLauncherFixture
    Assert 'original v0.1.1 launcher fixture compiled' ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $legacyLauncher)) $legacyLauncher
    foreach($operation in 'upgrade','uninstall'){
        foreach($condition in 'success','no-instance','invalid-token','timeout'){
            $label=$operation+'-'+$condition
            $target=Join-Path $testRoot $label
            $profile=Join-Path $testRoot ($label+'-profile')
            New-Item -ItemType Directory -Path $profile|Out-Null
            $env:WIN_VOICE_HOTKEY_DATA_DIR=$profile
            $config=Join-Path $profile 'config.ini'
            [IO.File]::WriteAllText($config,"[Mapping]`r`nEnabled=1`r`nKey=F24`r`nCloseKey=F24`r`n[Unrelated]`r`nValue=keep`r`n",[Text.Encoding]::Unicode)
            $configHash=(Get-FileHash -LiteralPath $config).Hash
            $install=Run $SetupExe ('--silent --isolated --target "'+$target+'"') ($label+' fresh install')
            Assert ($label+' installs without instance') ($install.ExitCode -eq 0) $install
            $sentinel=Join-Path $target 'keep-me-user.txt';[IO.File]::WriteAllText($sentinel,'Unrelated user file must survive both success and failure.')
            $launcher=Join-Path $target 'WinVoiceHotkey.exe'
            $retryLauncher=$launcher
            if($condition -eq 'timeout'){Copy-Item -LiteralPath $OldAppPathsFixture -Destination (Join-Path $target 'app\AppPaths.ahk') -Force}
            $current=$null
            if($condition -ne 'no-instance'){$current=StartInstance $launcher $profile $label}
            if($condition -eq 'timeout'){
                $retryLauncher=Join-Path $testRoot ($label+'-fixed-stop.exe')
                Copy-Item -LiteralPath $launcher -Destination $retryLauncher
                Copy-Item -LiteralPath $legacyLauncher -Destination $launcher -Force
                Record ($label+' legacy launcher installed') 'Original launcher can return zero without waiting; new setup must verify the runtime itself.'
            }
            $statePath=Join-Path $profile 'mapping-state.ini'
            $savedState=$null
            if($condition -eq 'invalid-token'){
                $savedState=[IO.File]::ReadAllBytes($statePath)
                $text=[IO.File]::ReadAllText($statePath)
                $bad=[regex]::Replace($text,'(?m)^InstanceToken=\d+','InstanceToken=0')
                if($bad -eq $text){throw 'Token fixture did not change state.'}
                [IO.File]::WriteAllText($statePath,$bad,[Text.Encoding]::Unicode)
            }
            $before=Snapshot $target
            $arguments='--silent --isolated '+$(if($operation -eq 'uninstall'){'--uninstall '}else{''})+'--target "'+$target+'"'
            $result=Run $SetupExe $arguments ($label+' action')
            if($condition -eq 'invalid-token' -or $condition -eq 'timeout'){
                $expected=if($condition -eq 'timeout'){3}else{2}
                Assert ($label+' rejects stop failure with exact code') ($result.ExitCode -eq $expected) $result
                Assert ($label+' Chinese retry guidance') ($result.StandardError.Contains('未继续覆盖或删除') -and $result.StandardError.Contains('重试')) $result.StandardError
                Assert ($label+' target files and directories unchanged') ((Snapshot $target) -eq $before) $null
                Assert ($label+' runtime remains alive without forced termination') ((Alive $current) -eq 2) $current
                if($savedState){[IO.File]::WriteAllBytes($statePath,$savedState)}
                # In the old mutex fixture the second stop cleans up; invalid-token is restored first.
                $stop=Run $retryLauncher '--stop' ($label+' user safe-exit retry')
                Assert ($label+' explicit safe exit succeeds') ($stop.ExitCode -eq 0 -and (Alive $current) -eq 0) $stop
                $current=$null
                $result=Run $SetupExe $arguments ($label+' retry action')
                Assert ($label+' operation succeeds after safe exit') ($result.ExitCode -eq 0) $result
            }else{
                Assert ($label+' succeeds') ($result.ExitCode -eq 0) $result
                if($current){Assert ($label+' previous runtime exited') ((Alive $current) -eq 0) $current}
                $current=$null
            }
            Assert ($label+' config preserved') ((Get-FileHash -LiteralPath $config).Hash -eq $configHash) $configHash
            Assert ($label+' unrelated file preserved') ((Test-Path -LiteralPath $sentinel) -and [IO.File]::ReadAllText($sentinel).Contains('Unrelated user file')) $sentinel
            if($operation -eq 'upgrade'){
                Assert ($label+' upgraded application remains installed') ((Test-Path -LiteralPath $launcher) -and (Test-Path -LiteralPath (Join-Path $target '.win-voice-hotkey-install'))) $target
                $current=StartInstance $launcher $profile ($label+' upgraded')
                $cleanup=Run $SetupExe ('--silent --isolated --uninstall --target "'+$target+'"') ($label+' upgraded cleanup')
                Assert ($label+' upgraded app starts and uninstalls') ($cleanup.ExitCode -eq 0 -and (Alive $current) -eq 0) $cleanup
                $current=$null
            }
            $remaining=@(Get-ChildItem -LiteralPath $target -Recurse -File)
            Assert ($label+' final target preserves only user sentinel') ($remaining.Count -eq 1 -and $remaining[0].Name -eq 'keep-me-user.txt') @($remaining|Select-Object Name)
        }
    }
    Assert 'guest has no project process after installer matrix' (@(Get-Process -Name WinVoiceHotkey,AutoHotkey64,VoicePanelBroker -ErrorAction SilentlyContinue).Count -eq 0) $null
    $complete=$true
}catch{$failure=$_.Exception.Message;($_|Out-String)|Set-Content -Encoding utf8 -LiteralPath (Join-Path $resultsDir 'failure.txt')}
finally{
    if($current){foreach($id in @([int]$current['PID'],[int]$current['CloseBrokerPID'])){$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$id);if($p){if(!$p.ExecutablePath.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup target outside this test root.'};Stop-Process -Id $id -Force}}}
    $env:WIN_VOICE_HOTKEY_DATA_DIR=$oldData
    @{Kind='InstallerStopOutcomeMatrix';Complete=$complete;Failure=$failure;TestRoot=$testRoot;MicrophoneUsed=$false;InputSent=$false;Observations=@($records.ToArray())}|ConvertTo-Json -Depth 10|Set-Content -Encoding utf8 -LiteralPath $ResultsPath
}
if(!$complete){exit 1}
