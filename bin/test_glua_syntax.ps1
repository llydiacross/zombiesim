[CmdletBinding()]
param(
    [string[]] $Path = @(),
    [string] $GluacPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GluacPath)) {
    $extensionRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
    $candidate = Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter 'venner.vscode-glua-enhanced-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'src\lib\gluac\gluac.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $candidate) {
        throw "gluac.exe was not found. Install the 'GLua Enhanced' VS Code extension (venner.vscode-glua-enhanced) or pass -GluacPath."
    }
    $GluacPath = $candidate
}
if (-not (Test-Path -LiteralPath $GluacPath -PathType Leaf)) {
    throw "gluac.exe was not found: $GluacPath"
}

if ($Path.Count -eq 0) {
    $Path = @((Join-Path $projectRoot 'gamemode'), (Join-Path $projectRoot 'entities'))
}
$files = @($Path | ForEach-Object {
    if (Test-Path -LiteralPath $_ -PathType Container) {
        Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.lua' -File
    } else {
        Get-Item -LiteralPath $_
    }
})

$failures = 0
foreach ($file in $files) {
    # gluac exits 0 even on syntax errors, so any output is treated as a failure.
    # PowerShell 5.1 turns redirected native stderr into a terminating error under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $output = (& $GluacPath -p $file.FullName 2>&1 | ForEach-Object { "$_" } | Out-String).Trim()
    $ErrorActionPreference = 'Stop'
    if ($output) {
        $failures++
        Write-Host "FAIL $($file.FullName): $output"
    }
}

Write-Host "$($files.Count) GLua file(s) checked, $failures failed."
if ($failures -gt 0) {
    exit 1
}
