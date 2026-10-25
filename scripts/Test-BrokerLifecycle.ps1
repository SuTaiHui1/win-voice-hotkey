[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$package=Join-Path $root 'out\package'
if(!(Test-Path -LiteralPath $package)){throw 'Build first.'}
$run=Join-Path $root ('out\broker-lifecycle-'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $run 'lifecycle-fixture'
New-Item -ItemType Directory -Path $fixture | Out-Null
Copy-Item -Path (Join-Path $package 'app\*.ahk') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $package 'app\VoicePanelBroker.exe') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $root 'tests\BrokerLifecycleFixture.ahk') -Destination $fixture
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$runner=Join-Path $run 'BrokerLifecycleRunner.exe'
& $csc /nologo /target:exe /platform:x64 /reference:System.Web.Extensions.dll ('/out:'+$runner) (Join-Path $root 'tests\BrokerLifecycleRunner.cs')
if($LASTEXITCODE -ne 0){throw 'Broker lifecycle runner compilation failed.'}
& $runner (Join-Path $package 'app\dependencies\AutoHotkey64.exe')
if($LASTEXITCODE -ne 0){throw ('Broker lifecycle failed/pending. Inspect own fixture/error files before retry: '+$run)}
$result=Get-Content -LiteralPath (Join-Path $fixture 'profile\lifecycle-results.json') -Raw | ConvertFrom-Json
if($result.passed -ne 26 -or $result.WinH_sent -or $result.microphone_used){throw 'Unexpected broker fixture result.'}
[pscustomobject]@{Passed=$result.passed;NoWinH=$true;NoMicrophone=$true;Results=$run}|ConvertTo-Json