[CmdletBinding()]
param(
    [ValidateSet('preview', 'city')]
    [string] $WorldProfile = 'preview',
    [string] $Map = 'zn_preview',
    [string] $GarrysModRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GarrysModRoot)) {
    $GarrysModRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}

$steamPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $GarrysModRoot))) 'steam.exe'
$gameExecutable = Join-Path $GarrysModRoot 'bin\win64\gmod.exe'
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    $gameExecutable = Join-Path $GarrysModRoot 'gmod.exe'
}
$logDirectory = Join-Path $GarrysModRoot 'garrysmod\logs'
if (-not (Test-Path -LiteralPath $steamPath -PathType Leaf)) {
    throw "Steam was not found: $steamPath"
}
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    throw "Garry's Mod was not found: $gameExecutable"
}

$arguments = @(
    '-applaunch', '4000',
    '-console', '-condebug', '-conclearlog', '-dev',
    '+sv_logfile', '1', '+sv_log_onefile', '1', '+sv_logecho', '1', '+log', 'on',
    '+gamemode', 'zombiesim', '+zombiesim_world_profile', $WorldProfile,
    '+map', $Map
)
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $steamPath
$startInfo.Arguments = ($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
$startInfo.UseShellExecute = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
if ($null -eq $process) {
    throw 'Steam did not start the Garry''s Mod launch request.'
}

Write-Output "Started ZombieSim through Steam (launcher process $($process.Id))."
Write-Output "Server logs: $logDirectory"
Write-Output "Console capture: $(Join-Path $GarrysModRoot 'console.log')"