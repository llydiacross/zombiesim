[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $GarrysModRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDirectory = Join-Path $PSScriptRoot '..\dist'
$moduleSource = Join-Path $sourceDirectory 'gmsv_zombiesimwalker_win64.dll'
$loaderSource = Join-Path $PSScriptRoot 'autorun\server\zombiesim_walker_loader.lua'
$gameDirectory = Join-Path $GarrysModRoot 'garrysmod'
$moduleDirectory = Join-Path $gameDirectory 'lua\bin'
$loaderDirectory = Join-Path $gameDirectory 'lua\autorun\server'
$moduleDestination = Join-Path $moduleDirectory 'gmsv_zombiesimwalker_win64.dll'
$loaderDestination = Join-Path $loaderDirectory 'zombiesim_walker_loader.lua'

if (-not (Test-Path -LiteralPath $gameDirectory -PathType Container)) {
    throw "Garry's Mod game directory was not found: $gameDirectory"
}
if (-not (Test-Path -LiteralPath $moduleSource -PathType Leaf)) {
    throw "Build the module first; missing artifact: $moduleSource"
}
if (-not (Test-Path -LiteralPath $loaderSource -PathType Leaf)) {
    throw "Missing loader source: $loaderSource"
}

if ($PSCmdlet.ShouldProcess($moduleDirectory, 'Create module directory')) {
    New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
}
if ($PSCmdlet.ShouldProcess($loaderDirectory, 'Create autorun directory')) {
    New-Item -ItemType Directory -Path $loaderDirectory -Force | Out-Null
}

$moduleNeedsCopy = $true
if (Test-Path -LiteralPath $moduleDestination -PathType Leaf) {
    $sourceHash = (Get-FileHash -LiteralPath $moduleSource -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $moduleDestination -Algorithm SHA256).Hash
    $moduleNeedsCopy = $sourceHash -ne $destinationHash
}

if ($moduleNeedsCopy -and $PSCmdlet.ShouldProcess($moduleDestination, 'Install walker module')) {
    Copy-Item -LiteralPath $moduleSource -Destination $moduleDestination -Force
}
if ($PSCmdlet.ShouldProcess($loaderDestination, 'Install walker loader')) {
    Copy-Item -LiteralPath $loaderSource -Destination $loaderDestination -Force
}

if (-not $WhatIfPreference) {
    $sourceHash = (Get-FileHash -LiteralPath $moduleSource -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $moduleDestination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw 'Installed walker module hash does not match the build artifact'
    }
    Write-Host "Installed walker module and loader under $gameDirectory"
}