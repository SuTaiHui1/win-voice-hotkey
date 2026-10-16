[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lock = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'dependencies.lock.json') | ConvertFrom-Json
$cache = Join-Path $root '.cache'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
function Get-VerifiedFile($Url, $File, $Hash) {
    if (!(Test-Path -LiteralPath $File)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $File
    }
    if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Hash) {
        throw "Dependency checksum mismatch: $(Split-Path $File -Leaf). Remove this cache file and obtain it again from the pinned official URL."
    }
}
Get-VerifiedFile $lock.autohotkey.runtimeUrl (Join-Path $cache 'AutoHotkey_2.0.30.zip') $lock.autohotkey.runtimeSha256
Get-VerifiedFile $lock.autohotkey.sourceUrl (Join-Path $cache 'AutoHotkey-v2.0.30-source.zip') $lock.autohotkey.sourceSha256
Write-Output 'Pinned AutoHotkey runtime and corresponding source verified.'
