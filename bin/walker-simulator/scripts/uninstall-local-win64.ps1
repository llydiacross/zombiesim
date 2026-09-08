[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $GarrysModRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gameDirectory = Join-Path $GarrysModRoot 'garrysmod'
$moduleDestination = Join-Path $gameDirectory 'lua\bin\gmsv_zombiesimwalker_win64.dll'
$loaderDestination = Join-Path $gameDirectory 'lua\autorun\server\zombiesim_walker_loader.lua'

if (-not (Test-Path -LiteralPath $gameDirectory -PathType Container)) {
    throw "Garry's Mod game directory was not found: $gameDirectory"
}

foreach ($path in @($loaderDestination, $moduleDestination)) {
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and $PSCmdlet.ShouldProcess($path, 'Remove walker installation')) {
        Remove-Item -LiteralPath $path -Force
    }
}