[CmdletBinding()]
param([switch]$UnitOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$package=Join-Path $root 'out\package'
if(!(Test-Path -LiteralPath $package)){throw 'Build first.'}
$testRoot=Join-Path $root ('out\tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
function Compile([string[]]$CompileArguments){& $csc @CompileArguments;if($LASTEXITCODE -ne 0){throw 'Test compilation failed.'}}
function RunFinite($file,$arguments,$name){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$file;$info.Arguments=$arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=[Diagnostics.Process]::Start($info);$null=$p.Handle
    try{
        if(!$p.WaitForExit(15000)){$p.Kill();throw ($name+' timed out.')}
        $stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd()
        [IO.File]::WriteAllText((Join-Path $testRoot ($name+'-stdout.txt')),$stdout)
        [IO.File]::WriteAllText((Join-Path $testRoot ($name+'-stderr.txt')),$stderr)
        if($p.ExitCode -ne 0){throw ($name+' failed. See '+$testRoot)}
        return $stdout
    }finally{$p.Dispose()}
}
$hostExe=Join-Path $testRoot 'TestDesktop.exe'
Compile @('/nologo','/target:exe','/platform:x64',('/out:'+$hostExe),(Join-Path $root 'src\host\TestDesktop.cs'))
Copy-Item -Path (Join-Path $root 'src\app\*.ahk') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $root 'tests\BindingUnitCheck.ahk') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $root 'tests\RuntimeStateUnitCheck.ahk') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $root 'tests\LanguageUnitCheck.ahk') -Destination $testRoot
Copy-Item -LiteralPath (Join-Path $root 'tests\BrokerIdleUnitCheck.ahk') -Destination $testRoot
$null=RunFinite $hostExe ('"'+(Join-Path $package 'app\dependencies\AutoHotkey64.exe')+'" "'+(Join-Path $testRoot 'BindingUnitCheck.ahk')+'"') 'binding'
$null=RunFinite $hostExe ('"'+(Join-Path $package 'app\dependencies\AutoHotkey64.exe')+'" "'+(Join-Path $testRoot 'RuntimeStateUnitCheck.ahk')+'"') 'runtime-state'
$null=RunFinite $hostExe ('"'+(Join-Path $package 'app\dependencies\AutoHotkey64.exe')+'" "'+(Join-Path $testRoot 'LanguageUnitCheck.ahk')+'"') 'language'
$null=RunFinite $hostExe ('"'+(Join-Path $package 'app\dependencies\AutoHotkey64.exe')+'" "'+(Join-Path $testRoot 'BrokerIdleUnitCheck.ahk')+'"') 'broker-idle'
$framework=Split-Path $csc -Parent
$refs=@('System.dll','System.Core.dll','System.Web.Extensions.dll',(Join-Path $framework 'WPF\UIAutomationClient.dll'),(Join-Path $framework 'WPF\UIAutomationTypes.dll'),(Join-Path $framework 'WPF\WindowsBase.dll'))
$coreExe=Join-Path $testRoot 'PanelCoreUnitCheck.exe'
Compile (@('/nologo','/target:exe','/platform:x64',('/out:'+$coreExe)) + @($refs | ForEach-Object {'/reference:'+$_}) + @((Join-Path $root 'src\app\VoicePanelCore.cs'),(Join-Path $root 'tests\PanelCoreUnitCheck.cs')))
$core=RunFinite $coreExe '' 'panel-core'
$result=@{BrokerIdle=(Get-Content -Raw -LiteralPath (Join-Path $testRoot 'broker-idle-unit-results.json')|ConvertFrom-Json);Language=(Get-Content -Raw -LiteralPath (Join-Path $testRoot 'language-unit-results.json')|ConvertFrom-Json);Binding=(Get-Content -Raw -LiteralPath (Join-Path $testRoot 'binding-unit-results.json') | ConvertFrom-Json);RuntimeState=(Get-Content -Raw -LiteralPath (Join-Path $testRoot 'runtime-state-unit-results.json') | ConvertFrom-Json);PanelCore=($core|ConvertFrom-Json)}
$result|ConvertTo-Json -Depth 8|Set-Content -Encoding utf8 -LiteralPath (Join-Path $testRoot 'results.json')
Write-Output ('Pure tests passed: '+$testRoot+'\results.json')
if(!$UnitOnly){
    if($env:USERNAME -ne 'WDAGUtilityAccount'){throw 'Normal-mode integration tests require Windows Sandbox. Pure tests passed; use -UnitOnly on the host.'}
    $setup=Get-ChildItem -LiteralPath (Join-Path $root 'out') -Filter '*-setup.exe'|Select-Object -First 1
    & (Join-Path $PSScriptRoot 'Test-Stop.ps1') -PackageRoot $package -SetupExe $setup.FullName -OldAppPathsFixture (Join-Path $root 'tests\fixtures\AppPaths-before-stop-fix.ahk') -ResultsPath (Join-Path $testRoot 'stop-results.json')
    & (Join-Path $PSScriptRoot 'Test-InstallerStop.ps1') -SetupExe $setup.FullName -OldAppPathsFixture (Join-Path $root 'tests\fixtures\AppPaths-before-stop-fix.ahk') -LegacyLauncherFixture (Join-Path $root 'tests\fixtures\Launcher-before-stop-fix.cs') -ResultsPath (Join-Path $testRoot 'installer-stop-results.json')
}
