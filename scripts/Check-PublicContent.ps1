[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$folders = 'src','scripts','tests','docs','third-party','.github'
$files = @()
foreach ($folder in $folders) { $files += Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File }
$files += Get-ChildItem -LiteralPath $root -File
$findings = @()
$sensitive = '(?i)(?:[A-Z]:\\Users\\[^\\\s"<>]+|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)'
foreach ($file in $files) {
    if ($file.FullName -eq (Join-Path $root 'docs\images\settings.png')) {
        $signature = [IO.File]::ReadAllBytes($file.FullName)
        if ($signature.Length -lt 8 -or [BitConverter]::ToString($signature[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'Invalid settings PNG.' }
        continue # This exact application-only image is reviewed visually for personal data.
    }
    if ($file.Extension -notin '.ahk','.cs','.ps1','.md','.json','.yml','.txt' -and $file.Name -notin '.gitignore','.gitattributes','LICENSE') { throw "Unexpected public file: $($file.Name)" }
    if ($file.Name -match '^(config|mapping-state)\.ini$|\.ndjson$|\.ready\.json$|\.wav$|\.log$') { throw "Runtime data found: $($file.Name)" }
    $content = [IO.File]::ReadAllText($file.FullName)
    if ($content -match $sensitive) { $findings += $file.FullName.Substring($root.Length + 1) }
}
if ($findings.Count) { throw ('Review required for possible personal paths or credentials in: ' + ($findings -join ', ')) }
Write-Output "Public text scan passed ($($files.Count) files). This pattern scan supplements manual review; it is not a security certification."
