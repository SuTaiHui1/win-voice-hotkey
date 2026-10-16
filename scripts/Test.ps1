[CmdletBinding()]
param([switch]$UnitOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$package = Join-Path $root 'out\package'
if (!(Test-Path -LiteralPath $package)) { throw 'Build first.' }
$testRoot = Join-Path $root ('out\tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testHost = Join-Path $testRoot 'TestDesktop.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:exe /platform:x64 ('/out:'+$testHost) (Join-Path $root 'src\host\TestDesktop.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test desktop host compilation failed.' }
$results = @()
foreach ($name in 'GlobalMappingUnitCheck','MouseMappingUnitCheck','CloseBindingsUnitCheck') {
    $folder = Join-Path $testRoot $name
    New-Item -ItemType Directory -Path $folder | Out-Null
    Copy-Item -Path (Join-Path $root 'src\app\*.ahk') -Destination $folder
    Copy-Item -LiteralPath (Join-Path $root "tests\$name.ahk") -Destination $folder
    $process = Start-Process -FilePath $testHost -ArgumentList @(('"'+(Join-Path $package 'app\dependencies\AutoHotkey64.exe')+'"'),('"'+(Join-Path $folder "$name.ahk")+'"')) -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $folder 'stderr.txt') -RedirectStandardOutput (Join-Path $folder 'stdout.txt')
    if (!$process.WaitForExit(15000)) { $process.Kill(); throw "$name timed out." }
    if ($process.ExitCode -ne 0) { throw "$name failed. See $folder" }
    $result = Get-ChildItem -LiteralPath $folder -Filter '*unit-results.json' | Select-Object -First 1
    if (!$result) { throw "$name did not produce a result." }
    $results += @{name=$name;result=(Get-Content -Raw -LiteralPath $result.FullName | ConvertFrom-Json)}
}
if ($UnitOnly) {
    $results | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'results.json')
    Write-Output "Unit tests passed. Results: $testRoot\results.json"
    return
}
# Exercise the extracted launcher and real settings UI with all global input
# hooks disabled. Existing user mappings and the microphone remain untouched.
$smoke = Join-Path $testRoot 'portable with spaces'
Copy-Item -Recurse -LiteralPath $package -Destination $smoke
$oldData = $env:WIN_VOICE_HOTKEY_DATA_DIR
try {
    $env:WIN_VOICE_HOTKEY_DATA_DIR = Join-Path $testRoot 'blank profile'
    $launcher = Start-Process -FilePath (Join-Path $smoke 'WinVoiceHotkey.exe') -ArgumentList '--smoke-test' -PassThru -WindowStyle Hidden
    if (!$launcher.WaitForExit(20000)) { $launcher.Kill(); throw 'Portable smoke timed out.' }
    if ($launcher.ExitCode -ne 0) { throw 'Portable smoke failed.' }
    $profile = $env:WIN_VOICE_HOTKEY_DATA_DIR
    if (!(Test-Path (Join-Path $profile 'smoke-results.json'))) { throw 'Smoke result missing.' }
    $results += @{name='portable-smoke';result=(Get-Content -Raw (Join-Path $profile 'smoke-results.json') | ConvertFrom-Json)}
    $state = Get-Content -Raw (Join-Path $profile 'mapping-state.ini')
    if ($state -notmatch 'Running=0') { throw 'Exit state not persisted.' }
    if ($state -match 'CloseBrokerPID=(\d+)' -and (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue)) { throw 'Helper still running after exit.' }
    # Repeat with the now-persisted profile.
    Remove-Item -LiteralPath (Join-Path $profile 'smoke-results.json')
    $repeat = Start-Process -FilePath (Join-Path $smoke 'WinVoiceHotkey.exe') -ArgumentList '--smoke-test' -PassThru -WindowStyle Hidden
    if (!$repeat.WaitForExit(20000) -or $repeat.ExitCode -ne 0) { throw 'Persisted profile restart failed.' }
    $setup = Get-ChildItem -LiteralPath (Join-Path $root 'out') -Filter '*-setup.exe' | Select-Object -First 1
    $install = Join-Path $testRoot 'installed with spaces'
    $installArgs = '--silent --isolated --target "' + $install + '"'
    $process = Start-Process -FilePath $setup.FullName -ArgumentList $installArgs -PassThru -WindowStyle Hidden
    if (!$process.WaitForExit(15000) -or $process.ExitCode -ne 0) { throw 'Isolated install failed.' }
    if (Test-Path (Join-Path $install 'portable.flag')) { throw 'Installed mode marker wrong.' }
    $env:WIN_VOICE_HOTKEY_DATA_DIR = Join-Path $testRoot 'installed blank profile'
    $process = Start-Process -FilePath (Join-Path $install 'WinVoiceHotkey.exe') -ArgumentList '--smoke-test' -PassThru -WindowStyle Hidden
    if (!$process.WaitForExit(20000) -or $process.ExitCode -ne 0) { throw 'Installed smoke failed.' }
    Set-Content -LiteralPath (Join-Path $install 'keep-me.txt') -Value 'Unrelated user file must survive uninstall.'
    # Run the original setup as uninstaller so no self-delete helper is needed.
    $uninstallArgs = '--silent --isolated --uninstall --target "' + $install + '"'
    $process = Start-Process -FilePath $setup.FullName -ArgumentList $uninstallArgs -PassThru -WindowStyle Hidden
    if (!$process.WaitForExit(15000) -or $process.ExitCode -ne 0) { throw 'Isolated uninstall failed.' }
    $remaining = @(Get-ChildItem -LiteralPath $install -Recurse -File)
    if ($remaining.Count -ne 1 -or $remaining[0].Name -ne 'keep-me.txt') { throw 'Uninstall removed an unrelated file or left installed files.' }
    if (!(Test-Path (Join-Path $env:WIN_VOICE_HOTKEY_DATA_DIR 'config.ini'))) { throw 'Uninstall removed preserved user config.' }
    $results += @{name='installer';result=@{install=$true;settings=$true;exit=$true;uninstall=$true;configPreserved=$true;unrelatedFilePreserved=$true;realStartupModified=$false}}
} finally { $env:WIN_VOICE_HOTKEY_DATA_DIR = $oldData }
$results | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'results.json')
Write-Output "Tests passed. Results: $testRoot\results.json"
