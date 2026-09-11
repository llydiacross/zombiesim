[CmdletBinding()]
param(
    [ValidateRange(1, 5000)]
    [int] $Lines = 250,
    [switch] $Console,
    [switch] $Follow,
    [string] $GarrysModRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GarrysModRoot)) {
    $GarrysModRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}

if ($Console) {
    $logPath = Join-Path $GarrysModRoot 'console.log'
} else {
    $logDirectory = Join-Path $GarrysModRoot 'garrysmod\logs'
    $logPath = Get-ChildItem -LiteralPath $logDirectory -Filter 'L-*.log' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($logPath) -or -not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw 'No Garry''s Mod log file is available yet.'
}

Write-Output "Reading $logPath"
if ($Follow) {
    Get-Content -LiteralPath $logPath -Tail $Lines -Wait
} else {
    Get-Content -LiteralPath $logPath -Tail $Lines
}