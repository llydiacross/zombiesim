param([string]$WorldProfile = 'preview', [string]$SettingsPath = '', [string]$PartialGapLayoutDirectory = '', [switch]$CompletePatches, [switch]$RepairUnmodifiedShapeWinding)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($RepairUnmodifiedShapeWinding) { throw 'Polygon infill is retired. The initializer creates rectangular ground sources only; preserve or archive legacy shapes through the cleanup audit.' }
Import-Module (Join-Path $PSScriptRoot 'terrain_infill.psm1')
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$terrain = Join-Path (Join-Path $root $profile.Settings.paths.templateDirectory) 'terrain'
$source = Join-Path $terrain 'tile_grass.vmf'
$text = [IO.File]::ReadAllText($source)
$directory = Join-Path $terrain 'infill'
[IO.Directory]::CreateDirectory($directory) | Out-Null
$specs = @(
    @{ name = 'tile_ground_full.vmf'; width = 640; height = 640 },
    @{ name = 'tile_ground_half.vmf'; width = 320; height = 640 },
    @{ name = 'tile_ground_quarter.vmf'; width = 320; height = 320 }
)
if (-not [string]::IsNullOrWhiteSpace($PartialGapLayoutDirectory)) {
    Import-Module (Join-Path $PSScriptRoot 'terrain_infill.psm1')
    $seen = @{}
    foreach ($file in Get-ChildItem -LiteralPath $PartialGapLayoutDirectory -Filter '*.layout.json' -File) {
        $layout = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        $contract = @(foreach ($name in @('motorwayCellInspection', 'motorwayAssembly')) { if ($null -ne $layout.PSObject.Properties[$name] -and $layout.$name.schemaVersion -eq 2) { $layout.$name } })
        if ($contract.Count -gt 1) { throw "Complete infill layout has more than one complex motorway contract: $($file.FullName)" }
        if ($contract.Count -eq 1 -and [IO.Path]::GetFileName($contract[0].template) -eq 'tile_motorway_corner_5x3.vmf') { continue }
        if ($null -eq $layout.PSObject.Properties['terrainInfill']) { continue }
        if ($CompletePatches -and $null -ne $layout.terrainInfill.PSObject.Properties['requiredRectangles']) {
            foreach ($piece in $layout.terrainInfill.requiredRectangles) {
                if (-not $seen.ContainsKey($piece.template)) {
                    $width = if ($piece.yaw -eq 90) { $piece.height } else { $piece.width }
                    $height = if ($piece.yaw -eq 90) { $piece.width } else { $piece.height }
                    $specs += @{ name = [IO.Path]::GetFileName($piece.template); width = $width; height = $height }
                    $seen[$piece.template] = $true
                }
            }
            continue
        }
        foreach ($gap in @($layout.terrainInfill.partialGaps | Where-Object rectangular)) {
            $split = Get-ZMInfillRectanglePieces $gap
            foreach ($piece in $split.pieces) {
                $name = $piece.template
                if (-not $seen.ContainsKey($name)) {
                    $width = if ($piece.yaw -eq 90) { $piece.height } else { $piece.width }
                    $height = if ($piece.yaw -eq 90) { $piece.width } else { $piece.height }
                    $specs += @{ name = [IO.Path]::GetFileName($name); width = $width; height = $height }
                    $seen[$name] = $true
                }
            }
            if ($split.unfilled.Count) { Write-Warning "Ground gap in $($file.Name) has a fractional or below-u4 remainder; no sub4/decimal source created." }
        }
        if (@($layout.terrainInfill.partialGaps | Where-Object { -not $_.rectangular }).Count) { throw "Ground coverage produced a nonrectangular gap: $($file.FullName). Polygon infill is prohibited." }
    }
}
foreach ($spec in $specs) {
    $path = Join-Path $directory $spec.name
    if (Test-Path -LiteralPath $path) {
        Write-Host "Preserving existing artist-owned infill template: $path"
        continue
    }
    $scaled = New-ZMInfillRectangleVmf $text $spec.width $spec.height
    [IO.File]::WriteAllText($path, $scaled, [Text.UTF8Encoding]::new($false))
    Write-Host "Created editable base infill template: $path"
}
