[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Get-Dependencies.ps1')
if (!(Test-Path -LiteralPath (Join-Path $root 'LICENSE'))) {
    throw 'Project LICENSE is missing; public release builds are blocked.'
}
$out = Join-Path $root 'out'
if (Test-Path -LiteralPath $out) { throw 'out already exists. Keep earlier artifacts or remove that exact generated directory before rebuilding.' }
$package = Join-Path $out 'package'
$app = Join-Path $package 'app'
New-Item -ItemType Directory -Force -Path $app,(Join-Path $app 'dependencies'),(Join-Path $package 'third-party-sources') | Out-Null
Copy-Item -Path (Join-Path $root 'src\app\*.ahk') -Destination $app
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$framework = Split-Path $csc -Parent
if (!(Test-Path -LiteralPath $csc)) { throw '.NET Framework 4.x 64-bit compiler is required on the build machine.' }
function Compile([string[]]$Arguments) { & $csc @Arguments; if ($LASTEXITCODE -ne 0) { throw 'C# compilation failed.' } }
$refs = @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Windows.Forms.dll',(Join-Path $framework 'WPF\UIAutomationClient.dll'),(Join-Path $framework 'WPF\UIAutomationTypes.dll'),(Join-Path $framework 'WPF\WindowsBase.dll'))
$argsBroker = @('/nologo','/target:winexe','/platform:x64','/optimize+','/debug-') + ($refs | ForEach-Object { '/reference:' + $_ }) + @(('/out:'+(Join-Path $app 'VoicePanelBroker.exe')),(Join-Path $root 'src\app\VoicePanelCore.cs'),(Join-Path $root 'src\app\VoicePanelBroker.cs'))
Compile $argsBroker
Compile @('/nologo','/target:winexe','/platform:x64','/optimize+','/debug-','/reference:System.Windows.Forms.dll',('/out:'+(Join-Path $package 'WinVoiceHotkey.exe')),(Join-Path $root 'src\host\Launcher.cs'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $root '.cache\AutoHotkey_2.0.30.zip'))
try {
    foreach ($name in 'AutoHotkey64.exe','license.txt') {
        [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry($name),(Join-Path $app "dependencies\$name"))
    }
} finally { $zip.Dispose() }
$lock = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'dependencies.lock.json') | ConvertFrom-Json
if ((Get-FileHash (Join-Path $app 'dependencies\AutoHotkey64.exe') -Algorithm SHA256).Hash -ne $lock.autohotkey.exeSha256) { throw 'Unexpected runtime binary.' }
Copy-Item -LiteralPath (Join-Path $root '.cache\AutoHotkey-v2.0.30-source.zip') -Destination (Join-Path $package 'third-party-sources')
foreach ($file in 'README.md','CHANGELOG.md','THIRD_PARTY_NOTICES.md','LICENSE') {
    if (Test-Path -LiteralPath (Join-Path $root $file)) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $package }
}
Copy-Item -Recurse -LiteralPath (Join-Path $root 'docs') -Destination $package
New-Item -ItemType File -Path (Join-Path $package 'portable.flag') | Out-Null
$version = '0.1.4'
$portable = Join-Path $out "win-voice-hotkey-$version-windows-x64-portable.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($package,$portable,[IO.Compression.CompressionLevel]::Optimal,$false)
$installer = Join-Path $out "win-voice-hotkey-$version-windows-x64-setup.exe"
Compile @('/nologo','/target:winexe','/platform:x64','/optimize+','/debug-','/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll',('/resource:'+$portable+',payload.zip'),('/out:'+$installer),'/main:Installer',(Join-Path $root 'src\host\Launcher.cs'),(Join-Path $root 'src\host\Installer.cs'))
$sources = Join-Path $out "win-voice-hotkey-$version-source.zip"
$sourceStage = Join-Path $out 'source'
New-Item -ItemType Directory -Path $sourceStage | Out-Null
foreach ($dir in 'src','scripts','tests','docs','third-party','.github') { Copy-Item -Recurse -LiteralPath (Join-Path $root $dir) -Destination $sourceStage }
foreach ($file in Get-ChildItem -LiteralPath $root -File) { Copy-Item -LiteralPath $file.FullName -Destination $sourceStage }
[IO.Compression.ZipFile]::CreateFromDirectory($sourceStage,$sources,[IO.Compression.CompressionLevel]::Optimal,$false)
$hashes = foreach ($file in $portable,$installer,$sources) { '{0}  {1}' -f (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path $file -Leaf) }
[IO.File]::WriteAllLines((Join-Path $out 'SHA256SUMS.txt'),$hashes,[Text.UTF8Encoding]::new($false))
Write-Output "Build ready: $version (unsigned)."
