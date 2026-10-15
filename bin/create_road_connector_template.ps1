param([string]$WorldProfile = 'preview', [string]$SettingsPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($profile.Name -ne 'preview') { throw 'The approved extended road connector is preview-only.' }
Import-Module (Join-Path $PSScriptRoot 'terrain_infill.psm1')
$root = Split-Path -Parent $PSScriptRoot
$roads = Join-Path (Join-Path $root $profile.Settings.paths.templateDirectory) 'roads'
$path = Join-Path $roads 'connectors\tile_road_straight_768.vmf'
if (Test-Path -LiteralPath $path -PathType Leaf) {
    Write-Host "Preserving existing editable road connector: $path"
} else {
    $source = [IO.File]::ReadAllText((Join-Path $roads 'tile_road.vmf'))
    # The straight's longitudinal brush endpoints extend by64 at each end; width/deck/UV stay unchanged.
    $extended = New-ZMInfillRectangleVmf $source 640 768
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $extended, [Text.UTF8Encoding]::new($false))
    Write-Host "Created approved editable 768-unit road connector: $path"
}
