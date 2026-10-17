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
    if ($file.Extension -notin '.ahk','.cs','.ps1','.md','.json','.yml','.txt' -and $file.Name -notin '.gitignore','.gitattributes','LICENSE') { throw "Unexpected public file: $($file.Name)" }
    if ($file.Name -match '^(config|mapping-state)\.ini$|\.ndjson$|\.ready\.json$|\.wav$|\.log$') { throw "Runtime data found: $($file.Name)" }
    $content = [IO.File]::ReadAllText($file.FullName)
    if ($content -match $sensitive) { $findings += $file.FullName.Substring($root.Length + 1) }
}
if ($findings.Count) { throw ('Review required for possible personal paths or credentials in: ' + ($findings -join ', ')) }
Write-Output "Public text scan passed ($($files.Count) files). This pattern scan supplements manual review; it is not a security certification."
