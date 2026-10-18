param(
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [string]$MapData = '',
    [string]$TrustedMotorwayPlan = '',
    [string[]]$CellCoordinates = @(),
    [switch]$StraightInspection,
    [switch]$NormalPlanOnly,
    [switch]$Normal,
    [switch]$NormalComplex,
    [switch]$SkipInfill,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modes = [System.Collections.Generic.List[string]]::new()
if ($StraightInspection) { $modes.Add('StraightInspection') }
if ($NormalPlanOnly) { $modes.Add('NormalPlanOnly') }
if ($Normal) { $modes.Add('Normal') }
if ($NormalComplex) { $modes.Add('NormalComplex') }
if ($modes.Count -ne 1) {
    throw 'Choose exactly one of -StraightInspection, -NormalPlanOnly, -Normal, or -NormalComplex.'
}
if ($CellCoordinates.Count -gt 0 -and -not $NormalComplex) {
    throw 'CellCoordinates is supported only with -NormalComplex.'
}
if ($SkipInfill -and -not $NormalComplex) {
    throw 'SkipInfill is supported only with -NormalComplex.'
}
if ([string]::IsNullOrWhiteSpace($MapData) -or -not (Test-Path -LiteralPath $MapData -PathType Leaf)) {
    throw 'Pass the current matching preview manifest with -MapData.'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw 'Pass an isolated output path with -OutputDirectory; dated generated defaults are not used.'
}

$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($profile.Name -ne 'preview') { throw 'Motorway cell previews are limited to the preview profile.' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$generatedRoot = [IO.Path]::GetFullPath((Join-Path $root 'generated')).TrimEnd('\') + '\'
if (-not $OutputDirectory.StartsWith($generatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Motorway cell output must remain under generated.'
}

$MapData = [IO.Path]::GetFullPath($MapData)
$sourceHash = (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash
$manifest = Get-Content -Raw -LiteralPath $MapData | ConvertFrom-Json
if ($manifest.map.gridCells -ne 24 -or $manifest.map.seed -ne 1337) {
    throw 'Motorway cell preview expects the approved 24x24 seed-1337 manifest.'
}

$normalMode = $NormalPlanOnly -or $Normal -or $NormalComplex
$trustedPlan = $null
if ($normalMode) {
    if ([string]::IsNullOrWhiteSpace($TrustedMotorwayPlan) -or
        -not (Test-Path -LiteralPath $TrustedMotorwayPlan -PathType Leaf)) {
        throw 'Normal motorway previews require an explicit current -TrustedMotorwayPlan.'
    }
    $TrustedMotorwayPlan = [IO.Path]::GetFullPath($TrustedMotorwayPlan)
    $trustedPlan = Get-Content -Raw -LiteralPath $TrustedMotorwayPlan | ConvertFrom-Json
    if ($trustedPlan.mapSeed -ne [int]$manifest.map.seed -or
        $trustedPlan.mapGridCells -ne [int]$manifest.map.gridCells) {
        throw 'Trusted motorway plan and preview manifest must use the same seed and grid.'
    }
}

if ($NormalComplex) {
    $cells = @($manifest.cells | Where-Object {
        $_.highway.present -and $null -eq $_.safeZone -and @($_.landmarks).Count -eq 0 -and
        -not ((@($_.highway.connections | Sort-Object) -join ',') -in @('N,S', 'E,W') -and
            -not $_.highway.bridge -and @($_.highway.rampExits).Count -eq 0)
    })
    if ($cells.Count -eq 0) { throw 'No complex motorway cells found in the manifest.' }
    if ($CellCoordinates.Count -gt 0) {
        $requested = @{}
        foreach ($coordinate in $CellCoordinates) {
            if ($coordinate -notmatch '^(?<x>\d+),(?<y>\d+)$') { throw "Invalid logical coordinate '$coordinate'." }
            if ($requested.ContainsKey($coordinate)) { throw "Duplicate logical coordinate '$coordinate'." }
            $requested[$coordinate] = $true
        }
        $cells = @($cells | Where-Object { $requested.ContainsKey("$($_.x),$($_.y)") })
        if ($cells.Count -ne $requested.Count) {
            $found = @($cells | ForEach-Object { "$($_.x),$($_.y)" })
            $missing = @($requested.Keys | Where-Object { $_ -notin $found })
            throw "Trusted preview is missing requested complex motorway cells: $($missing -join ', ')."
        }
    }
} else {
    $targets = @(
        [pscustomobject]@{ x = 6; y = 1; orientation = 'vertical'; connections = 'N,S' },
        [pscustomobject]@{ x = 2; y = 7; orientation = 'horizontal'; connections = 'E,W' }
    )
    $cells = @(foreach ($target in $targets) {
        $matches = @($manifest.cells | Where-Object { $_.x -eq $target.x -and $_.y -eq $target.y })
        if ($matches.Count -ne 1) { throw "Missing/duplicate straight preview cell $($target.x),$($target.y)." }
        $cell = $matches[0]
        if (-not $cell.highway.present -or
            (@($cell.highway.connections | Sort-Object) -join ',') -ne $target.connections -or
            $cell.highway.bridge -or @($cell.highway.rampExits).Count -gt 0 -or
            $null -ne $cell.safeZone -or @($cell.landmarks).Count -gt 0) {
            throw "Preview cell $($target.x),$($target.y) is no longer the approved plain $($target.orientation) straight."
        }
        $cell
    })
}

if ($normalMode) {
    $trustedByCoordinate = @{}
    foreach ($cell in $trustedPlan.cells) {
        $coordinate = "$($cell.x),$($cell.y)"
        if ($trustedByCoordinate.ContainsKey($coordinate)) { throw "Trusted plan repeats cell $coordinate." }
        $trustedByCoordinate[$coordinate] = $cell
    }
    foreach ($cell in $cells) {
        $coordinate = "$($cell.x),$($cell.y)"
        if (-not $trustedByCoordinate.ContainsKey($coordinate)) { throw "Trusted plan has no contract for $coordinate." }
        $trusted = $trustedByCoordinate[$coordinate]
        if ($trusted.topology -cne $cell.topology -or $trusted.transportFeature -cne $cell.transportFeature -or
            (@($trusted.activeEntrances | Sort-Object -Unique) -join ',') -cne
            (@($cell.activeEntrances | Sort-Object -Unique) -join ',')) {
            throw "Trusted plan topology, transport, or entrances differ at $coordinate."
        }
        $contract = $trusted.motorwayAssembly
        $authority = if ($null -ne $contract) { $contract.PSObject.Properties['assemblyAuthority'] } else { $null }
        if ($null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout' -or
            @($contract.gates).Count -eq 0) {
            throw "Trusted plan has no approved gate records at $coordinate."
        }
    }
}

$manifest.cells = $cells
$manifest.safeZones = @()
$settings = $profile.Settings
$settings.vmfBuild.outerEdges.enabled = $true
$templateRoot = Join-Path $root $settings.paths.templateDirectory
foreach ($path in @($settings.cellPlanning.topologyTemplates.Values) +
    @($settings.cellPlanning.transportTemplates.Values) + @($settings.vmfBuild.border.cornerTemplate)) {
    if (-not (Test-Path -LiteralPath (Join-Path $templateRoot $path) -PathType Leaf)) {
        throw "Preview settings source is missing: $path"
    }
}

Import-Module (Join-Path $PSScriptRoot 'vmf_source_dependencies.psm1') -Force
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$isolatedSettings = Join-Path $OutputDirectory 'settings.json'
$fixtureMap = Join-Path $OutputDirectory 'fixture-map.json'
$planPath = Join-Path $OutputDirectory 'plan.json'
$listPath = Join-Path $OutputDirectory 'required.txt'
$src = Join-Path $OutputDirectory 'src'
$skybox = Join-Path $OutputDirectory 'skybox'
Write-TextFileIfChanged -Path $isolatedSettings -Content ($settings | ConvertTo-Json -Depth 100) | Out-Null
Write-TextFileIfChanged -Path $fixtureMap -Content ($manifest | ConvertTo-Json -Depth 30) | Out-Null

$plannerArguments = @{
    WorldProfile = 'preview'; SettingsPath = $isolatedSettings; MapData = $fixtureMap
    CellDirectory = $src; Output = $planPath; ListOutput = $listPath
}
if ($normalMode) {
    $plannerArguments.TrustedMotorwayPlan = $TrustedMotorwayPlan
} else {
    $plannerArguments.MotorwayCellInspection = $true
}
& (Join-Path $PSScriptRoot 'plan_cell_templates.ps1') @plannerArguments | Out-Null
if (-not $?) { throw 'Motorway cell planner failed.' }

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
foreach ($cell in $plan.cells) {
    if ($normalMode) {
        $authority = $cell.motorwayAssembly.PSObject.Properties['assemblyAuthority']
        if ($null -ne $cell.PSObject.Properties['motorwayCellInspection'] -or
            $null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout') {
            throw "Normal plan contains an untrusted/inspection motorway contract at $($cell.x),$($cell.y)."
        }
    } elseif ($null -eq $cell.PSObject.Properties['motorwayCellInspection']) {
        throw "Straight inspection plan lacks its explicit inspection contract at $($cell.x),$($cell.y)."
    }
}
if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) {
    throw 'Source manifest changed during motorway cell planning.'
}
if ($NormalPlanOnly) {
    $plan.cells | ForEach-Object {
        [pscustomobject]@{
            gridX = $_.x; gridY = $_.y; topology = $_.topology
            vmf = $_.cellTemplateFilename; gates = @($_.motorwayAssembly.gates).Count
        }
    }
    return
}

$builderArguments = @{
    WorldProfile = 'preview'; SettingsPath = $isolatedSettings; PlanData = $planPath
    CellDirectory = $src; SkyboxOutputDirectory = $skybox; RefreshGenerated = $true
}
if ($StraightInspection) { $builderArguments.MotorwayCellInspection = $true }
if ($NormalComplex -and -not $SkipInfill) { $builderArguments.MeasureCompleteTerrainInfill = $true }
& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') @builderArguments | Out-Null
if (-not $?) { throw 'Motorway cell VMF generation failed.' }
if ($NormalComplex -and -not $SkipInfill) {
    & (Join-Path $PSScriptRoot 'create_terrain_infill_templates.ps1') -WorldProfile preview `
        -SettingsPath $isolatedSettings -PartialGapLayoutDirectory $src -CompletePatches | Out-Null
    if (-not $?) { throw 'Normal complex terrain-base creation failed.' }
    & (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $isolatedSettings `
        -PlanData $planPath -CellDirectory $src -SkyboxOutputDirectory $skybox -RefreshGenerated `
        -SizedTerrainInfill -CompleteTerrainInfill | Out-Null
    if (-not $?) { throw 'Normal complex infill rebuild failed.' }
}
if ($sourceHash -cne (Get-FileHash -LiteralPath $MapData -Algorithm SHA256).Hash) {
    throw 'Source manifest changed during motorway cell generation.'
}
$plan.cells | ForEach-Object {
    [pscustomobject]@{
        gridX = $_.x; gridY = $_.y; topology = $_.topology; transport = $_.transportFeature
        vmf = Join-Path $src $_.cellTemplateFilename
        status = if ($StraightInspection) { 'straight_inspection_only' } else { 'trusted_normal_plan_not_compiled' }
    }
}
