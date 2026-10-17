[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$SetupExe,
    [Parameter(Mandatory=$true)][string]$OldAppPathsFixture,
    [Parameter(Mandatory=$true)][string]$ResultsPath
)
$ErrorActionPreference='Stop'
if($env:USERNAME -ne 'WDAGUtilityAccount') {
    throw 'This normal-mode regression installs guest input hooks. Run only in Windows Sandbox as WDAGUtilityAccount.'
}
$testRoot=Join-Path $env:TEMP ('WinVoiceHotkeyStopRegression-'+[guid]::NewGuid().ToString('N'))
$resultsDir=Split-Path ([IO.Path]::GetFullPath($ResultsPath)) -Parent
New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop|Out-Null
if(-not (Test-Path $resultsDir)){New-Item -ItemType Directory -Path $resultsDir|Out-Null}
$records=New-Object Collections.Generic.List[object]
$oldData=$env:WIN_VOICE_HOTKEY_DATA_DIR
$oldDiag=$env:WIN_VOICE_HOTKEY_DIAG_LOG
$current=$null;$failure=$null;$complete=$false
function Record($name,$value){$entry=[ordered]@{Name=$name;Utc=[DateTime]::UtcNow.ToString('o');Value=$value};$records.Add($entry);$entry|ConvertTo-Json -Depth 6 -Compress|Add-Content (Join-Path $resultsDir 'checks.jsonl') -Encoding UTF8}
function Assert($name,[bool]$passed,$details){Record $name @{Passed=$passed;Details=$details};if(-not $passed){throw ('Stop regression failed: '+$name)}}
function Run($file,$arguments,$label,[bool]$capture=$true){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$file;$info.Arguments=$arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardError=$capture
    $timer=[Diagnostics.Stopwatch]::StartNew();$p=[Diagnostics.Process]::Start($info);$null=$p.Handle
    if(-not $p.WaitForExit(20000)){throw ('Command timeout: '+$label)}
    $errorText=if($capture){[string]$p.StandardError.ReadToEnd()}else{''}
    $result=[ordered]@{Executable=$file;Arguments=$arguments;PID=$p.Id;ExitCode=[int]$p.ExitCode;Milliseconds=$timer.ElapsedMilliseconds;StandardError=$errorText}
    Record $label $result;$p.Dispose();return $result
}
function State{
    $s=@{};$path=Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'mapping-state.ini'
    if(Test-Path $path){foreach($line in [IO.File]::ReadAllLines($path)){if($line -match '^([^=\[]+)=([^\r\n]*)$'){$s[$Matches[1]]=$Matches[2]}}}
    return $s
}
function StartInstance($launcher,$label){
    $start=Run $launcher '' ($label+' launch') $false
    Assert ($label+' launcher success') ($start.ExitCode -eq 0) $start
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do{$s=State;$process=if($s.ContainsKey('PID')){Get-CimInstance Win32_Process -Filter ('ProcessId='+$s['PID'])}else{$null};if($s['Running'] -eq '1' -and $s['CloseBrokerReady'] -eq '1' -and $process -and $process.ExecutablePath.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
    Assert ($label+' runtime and broker ready') ($s['Running'] -eq '1' -and $s['CloseBrokerReady'] -eq '1' -and $process -and $process.ExecutablePath.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)) $s
    return $s
}
function Remaining($s){return @(Get-Process -Id ([int]$s['PID']),([int]$s['CloseBrokerPID']) -ErrorAction SilentlyContinue|Select-Object ProcessName,Id)}
function Exited($s,$label){
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{$left=Remaining $s;if($left.Count -eq 0){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $deadline)
    $state=State
    Assert $label ($left.Count -eq 0 -and $state['Running'] -eq '0') @{Remaining=$left;State=$state}
    Copy-Item (Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'mapping-state.ini') (Join-Path $resultsDir ($label+'-state.ini'))
}
try{
    Assert 'no preexisting guest mapping process' (@(Get-Process -Name WinVoiceHotkey,AutoHotkey64,VoicePanelBroker -ErrorAction SilentlyContinue).Count -eq 0) @{Guest=$env:COMPUTERNAME;Identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name}
    $env:WIN_VOICE_HOTKEY_DIAG_LOG=$null
    $portable=Join-Path $testRoot 'portable with spaces'
    Copy-Item -LiteralPath $PackageRoot -Destination $portable -Recurse
    $launcher=Join-Path $portable 'WinVoiceHotkey.exe'
    $env:WIN_VOICE_HOTKEY_DATA_DIR=Join-Path $testRoot 'portable profile'
    $result=Run $launcher '--stop' 'missing-state no-op'
    Assert 'no known state is successful no-op' ($result.ExitCode -eq 0) $result
    $result=Run $launcher '--smoke-test' 'local package smoke'
    $smokePath=Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'smoke-results.json'
    $smoke=[IO.File]::ReadAllText($smokePath)|ConvertFrom-Json
    Assert 'local no-input smoke succeeds' ($result.ExitCode -eq 0 -and $smoke.settings_opened -and $smoke.settings_closed -and $smoke.broker_ready -and $smoke.hooks_installed -eq $false -and $smoke.microphone_used -eq $false) $smoke
    Copy-Item $smokePath (Join-Path $resultsDir 'smoke-results.json')

    $current=StartInstance $launcher 'normal-first-start'
    $result=Run $launcher '--stop' 'normal first stop'
    Assert 'first stop confirms exit zero' ($result.ExitCode -eq 0) $result
    Exited $current 'normal-first-stop-exited'
    $result=Run $launcher '--stop' 'recorded-instance-already-exited'
    Assert 'recorded absent instance is successful no-op' ($result.ExitCode -eq 0) $result

    $config=Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'config.ini'
    [IO.File]::WriteAllText($config,"[Mapping]`r`nEnabled=1`r`nKey=Tab`r`nCloseKey=MButton`r`n",[Text.Encoding]::Unicode)
    $hash=(Get-FileHash $config).Hash
    $current=StartInstance $launcher 'persisted-profile-start'
    Assert 'persisted keys load in canonical form' ($current['Key'] -eq 'sc00F' -and $current['CloseKey'] -eq 'MButton') $current
    $statePath=Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'mapping-state.ini'
    foreach($case in @(@{Name='invalid PID';Pattern='(?m)^PID=\d+';Replacement='PID=not-a-pid'},@{Name='invalid token';Pattern='(?m)^InstanceToken=\d+';Replacement='InstanceToken=0'})){
        $saved=[IO.File]::ReadAllBytes($statePath)
        try{
            $text=[IO.File]::ReadAllText($statePath);$bad=[regex]::Replace($text,$case.Pattern,$case.Replacement)
            if($bad -eq $text){throw 'Invalid-state fixture did not change the expected field'}
            [IO.File]::WriteAllText($statePath,$bad,[Text.Encoding]::Unicode)
            $result=Run $launcher '--stop' $case.Name
            Assert ($case.Name+' rejects with exit 2 and error feedback') ($result.ExitCode -eq 2 -and -not [string]::IsNullOrWhiteSpace($result.StandardError) -and (Remaining $current).Count -eq 2) $result
        }finally{[IO.File]::WriteAllBytes($statePath,$saved)}
    }
    $result=Run $launcher '--stop' 'restored-state valid stop'
    Assert 'restored state stops successfully' ($result.ExitCode -eq 0) $result
    Exited $current 'restored-state-stop-exited'
    Assert 'normal stop preserves user configuration' ((Get-FileHash $config).Hash -eq $hash) @{SHA256=$hash}

    # Replay the pre-fix runtime only in a temporary test copy to exercise exit-code 3.
    $timeoutPackage=Join-Path $testRoot 'deliberately unfixed timeout fixture'
    Copy-Item -LiteralPath $PackageRoot -Destination $timeoutPackage -Recurse
    Copy-Item -LiteralPath $OldAppPathsFixture -Destination (Join-Path $timeoutPackage 'app\AppPaths.ahk') -Force
    $timeoutLauncher=Join-Path $timeoutPackage 'WinVoiceHotkey.exe'
    $env:WIN_VOICE_HOTKEY_DATA_DIR=Join-Path $testRoot 'timeout profile'
    $current=StartInstance $timeoutLauncher 'timeout-fixture'
    $result=Run $timeoutLauncher '--stop' 'deliberately unfixed timeout'
    Assert 'non-exiting runtime reports exit 3 and error feedback' ($result.ExitCode -eq 3 -and -not [string]::IsNullOrWhiteSpace($result.StandardError) -and (Remaining $current).Count -eq 2) $result
    $result=Run $timeoutLauncher '--stop' 'timeout fixture second-stop cleanup'
    Assert 'fixture cleanup stop confirms exit' ($result.ExitCode -eq 0) $result
    Exited $current 'timeout-fixture-cleaned'

    $installed=Join-Path $testRoot 'installed with spaces'
    $env:WIN_VOICE_HOTKEY_DATA_DIR=Join-Path $testRoot 'installed profile'
    $result=Run $SetupExe ('--silent --isolated --target "'+$installed+'"') 'install local staging build'
    Assert 'local setup installs in isolated target' ($result.ExitCode -eq 0 -and (Test-Path (Join-Path $installed '.win-voice-hotkey-install')) -and -not (Test-Path (Join-Path $installed 'portable.flag'))) $result
    $installedLauncher=Join-Path $installed 'WinVoiceHotkey.exe'
    $current=StartInstance $installedLauncher 'installed-normal-start'
    $result=Run $installedLauncher '--stop' 'installed first stop'
    Assert 'installed first stop confirms exit' ($result.ExitCode -eq 0) $result
    Exited $current 'installed-first-stop-exited'
    $current=StartInstance $installedLauncher 'running-uninstall-start'
    $sentinel=Join-Path $installed 'keep-me-regression.txt';[IO.File]::WriteAllText($sentinel,'Unrelated regression file must survive uninstall.')
    $installedConfig=Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'config.ini';$installedConfigHash=(Get-FileHash $installedConfig).Hash
    $result=Run $SetupExe ('--silent --isolated --uninstall --target "'+$installed+'"') 'normal running-app uninstall'
    Assert 'running-app happy-path uninstall succeeds' ($result.ExitCode -eq 0 -and (Remaining $current).Count -eq 0) $result
    $remaining=@(Get-ChildItem $installed -File -Recurse)
    Assert 'uninstall preserves only unrelated sentinel in target' ($remaining.Count -eq 1 -and $remaining[0].Name -eq 'keep-me-regression.txt' -and (Test-Path -LiteralPath $sentinel)) @($remaining|Select-Object FullName,Length)
    Assert 'uninstall preserves user configuration' ((Get-FileHash $installedConfig).Hash -eq $installedConfigHash) @{SHA256=$installedConfigHash}
    Assert 'guest contains no project processes after tests' (@(Get-Process -Name WinVoiceHotkey,AutoHotkey64,VoicePanelBroker -ErrorAction SilentlyContinue).Count -eq 0) @()
    $complete=$true
}catch{$failure=$_.Exception.Message;$_|Out-String|Set-Content (Join-Path $resultsDir 'failure.txt') -Encoding UTF8}
finally{
    if($current){foreach($id in @([int]$current['PID'],[int]$current['CloseBrokerPID'])){$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$id);if($p){if(-not $p.ExecutablePath.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup target outside this test root'};Stop-Process -Id $id -Force;Record 'failed-test process cleanup' @{PID=$id;Path=$p.ExecutablePath}}}}
    $env:WIN_VOICE_HOTKEY_DATA_DIR=$oldData;$env:WIN_VOICE_HOTKEY_DIAG_LOG=$oldDiag
    [ordered]@{Kind='LocalStopFixNormalModeRegression';Complete=$complete;Failure=$failure;Guest=$env:COMPUTERNAME;Identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;FinishedUtc=[DateTime]::UtcNow.ToString('o');TestRoot=$testRoot;PackageRoot=$PackageRoot;SetupExe=$SetupExe;MicrophoneUsed=$false;InputSent=$false;Observations=$records}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ResultsPath -Encoding UTF8
}
if(-not $complete){exit 1}
