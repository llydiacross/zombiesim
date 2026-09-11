[CmdletBinding()]
param(
    [ValidateRange(1, 60)]
    [int] $GracefulTimeoutSeconds = 15,
    [switch] $Force,
    [string] $GarrysModRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GarrysModRoot)) {
    $GarrysModRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}

$gameExecutable = Join-Path $GarrysModRoot 'bin\win64\gmod.exe'
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    $gameExecutable = Join-Path $GarrysModRoot 'gmod.exe'
}
$processes = @(
    Get-Process -Name 'gmod' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $gameExecutable }
)
if ($processes.Count -eq 0) {
    Write-Output 'No local Garry''s Mod process is running.'
    return
}

foreach ($process in $processes) {
    if (-not $process.CloseMainWindow()) {
        if (-not $Force) {
            throw "Garry's Mod process $($process.Id) has no closable main window. Re-run with -Force to terminate it."
        }
        Stop-Process -Id $process.Id -Force
        continue
    }
    if (-not $process.WaitForExit($GracefulTimeoutSeconds * 1000)) {
        if (-not $Force) {
            throw "Garry's Mod process $($process.Id) did not exit in $GracefulTimeoutSeconds seconds. Re-run with -Force to terminate it."
        }
        Stop-Process -Id $process.Id -Force
    }
}

Write-Output 'Garry''s Mod stopped.'