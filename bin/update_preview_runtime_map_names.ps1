param(
    [Parameter(Mandatory = $true)][string]$PlanData,
    [Parameter(Mandatory = $true)][string]$RuntimeWorldData,
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$ContentMapDirectory,
    [Parameter(Mandatory = $true)][string]$EngineMapDirectory,
    [Parameter(Mandatory = $true)][string]$Output,
    [Parameter(Mandatory = $true)][string]$SkyboxManifest,
    [Parameter(Mandatory = $true)][string]$SkyboxOutput,
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedWorldProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') `
    -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($resolvedWorldProfile.Name -ne 'preview') { throw 'Map-name-only runtime updates are restricted to preview.' }

function Resolve-ProjectPath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $projectRoot $Path))
}

function Get-CellDataSignature {
    param([object]$Cell)

    $fields = [ordered]@{}
    foreach ($property in $Cell.PSObject.Properties) {
        if ($property.Name -ne 'map') { $fields[$property.Name] = $property.Value }
    }
    return $fields | ConvertTo-Json -Depth 30 -Compress
}

function Set-JsonProperty {
    param([object]$Object, [string]$Name, [object]$Value)

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Remove-JsonProperty {
    param([object]$Object, [string]$Name)

    if ($null -ne $Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

$planPath = Resolve-ProjectPath $PlanData
$runtimePath = Resolve-ProjectPath $RuntimeWorldData
$buildPath = Resolve-ProjectPath $BuildDirectory
$contentMapsPath = Resolve-ProjectPath $ContentMapDirectory
$engineMapsPath = Resolve-ProjectPath $EngineMapDirectory
$outputPath = Resolve-ProjectPath $Output
$skyboxManifestPath = Resolve-ProjectPath $SkyboxManifest
$skyboxOutputPath = Resolve-ProjectPath $SkyboxOutput

foreach ($path in @($planPath, $runtimePath, $skyboxManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required runtime map update input is missing: $path"
    }
}
foreach ($path in @($buildPath, $contentMapsPath, $engineMapsPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Required staged map directory is missing: $path"
    }
}
if ($runtimePath -ieq $outputPath) {
    throw 'Write the candidate runtime data to a separate file before staging it.'
}
if ($skyboxManifestPath -ieq $skyboxOutputPath -or $outputPath -ieq $skyboxOutputPath) {
    throw 'Write the candidate skyline manifest to a separate file from both source and runtime outputs.'
}

$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$baseJson = Get-Content -LiteralPath $runtimePath -Raw
$original = $baseJson | ConvertFrom-Json
$updated = $baseJson | ConvertFrom-Json
$skyboxBaseJson = Get-Content -LiteralPath $skyboxManifestPath -Raw
$skyboxBase = $skyboxBaseJson | ConvertFrom-Json
$skyboxUpdated = $skyboxBaseJson | ConvertFrom-Json
if ($plan.schemaVersion -lt 2 -or $original.schemaVersion -lt 1) {
    throw 'Runtime map-name updates require a schema-2 plan and schema-1 runtime world.'
}
if ($original.world.profileId -ne 'preview') { throw 'The base runtime world is not the preview profile.' }
if ($skyboxBase.schemaVersion -ne 2 -or $skyboxBase.profile -ne 'preview' -or
    $skyboxBase.templatePlanSha256 -ne $original.world.templatePlanSha256 -or
    $null -eq $skyboxBase.geometry -or $null -eq $skyboxBase.recipes) {
    throw 'The base skyline manifest does not match the active expanded preview runtime.'
}

$boundsKeys = @('revision', 'tileSize', 'coreTileGridSize', 'coreHalfExtent', 'traversableHalfExtent',
    'visualHalfExtent', 'neighbourPitch', 'coastContactHalfExtent', 'playableCeiling')
foreach ($key in $boundsKeys) {
    if ($skyboxBase.cellBounds.$key -ne $original.world.cellBounds.$key -or
        $plan.cellBounds.$key -ne $skyboxBase.cellBounds.$key) {
        throw "Skyline, plan and runtime bounds differ: $key"
    }
}

$grid = @($original.world.grid)
$width = [int]$plan.mapGridCells
$gridMatches = $grid.Count -eq 2 -and $grid[0] -eq $width -and $grid[1] -eq $width
$seedMatches = [int]$original.world.seed -eq [int]$plan.mapSeed
if (-not $gridMatches -or -not $seedMatches) {
    throw 'The partial plan does not match the preview runtime grid and seed.'
}
if (@($plan.cells).Count -eq 0 -or @($original.cells).Count -ne ($width * $width)) {
    throw 'The plan must select cells from a complete preview runtime grid.'
}

$runtimeById = @{}
foreach ($cell in $original.cells) {
    $key = [string]$cell.id
    if ($runtimeById.ContainsKey($key)) { throw "Duplicate runtime cell id: $key" }
    $runtimeById[$key] = $cell
}

$updatedById = @{}
foreach ($cell in $updated.cells) { $updatedById[[string]$cell.id] = $cell }
$planCellDirectory = Resolve-ProjectPath ([string]$plan.cellDirectory)
$seenIds = @{}
$updates = [System.Collections.Generic.List[object]]::new()
$skyboxUpdates = [System.Collections.Generic.List[object]]::new()
foreach ($plannedCell in $plan.cells) {
    $x = [int]$plannedCell.x
    $y = [int]$plannedCell.y
    if ($x -lt 0 -or $x -ge $width -or $y -lt 0 -or $y -ge $width) {
        throw "Partial plan cell is outside the runtime grid: $x,$y"
    }

    $id = ($y * $width) + $x
    $key = [string]$id
    if ($seenIds.ContainsKey($key)) { throw "Partial plan repeats logical cell $x,$y" }
    if (-not $runtimeById.ContainsKey($key)) { throw "Runtime world has no logical cell $x,$y" }
    $seenIds[$key] = $true

    $runtimeCell = $runtimeById[$key]
    if ($runtimeCell.topology -ne $plannedCell.topology) {
        throw "Topology differs for logical cell $x,$y."
    }
    $plannedEntrances = @($plannedCell.activeEntrances | Sort-Object -Unique)
    $runtimeEntrances = @($runtimeCell.entrances | Sort-Object -Unique)
    if (($plannedEntrances -join ',') -cne ($runtimeEntrances -join ',')) {
        throw "Active entrances differ for logical cell $x,$y."
    }
    if ($null -ne $plannedCell.PSObject.Properties['gateDirections']) {
        $plannedGates = @($plannedCell.gateDirections | Sort-Object -Unique)
        $runtimeGates = @($runtimeCell.motorwayGates | ForEach-Object { $_.direction } | Sort-Object -Unique)
        if (($plannedGates -join ',') -cne ($runtimeGates -join ',')) {
            throw "Gate directions differ for logical cell $x,$y."
        }
    }

    $vmfName = [IO.Path]::GetFileName([string]$plannedCell.cellTemplateFilename)
    if ([IO.Path]::GetExtension($vmfName) -ne '.vmf' -or $vmfName -notlike 'zz_preview_*.vmf') {
        throw "Partial preview plan has an invalid recipe name for logical cell $x,$y."
    }
    $mapName = [IO.Path]::GetFileNameWithoutExtension($vmfName)
    $sourcePath = Join-Path $planCellDirectory $vmfName
    $layoutPath = [IO.Path]::ChangeExtension($sourcePath, '.layout.json')
    $sourceExists = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $layoutExists = Test-Path -LiteralPath $layoutPath -PathType Leaf
    if (-not $sourceExists -or -not $layoutExists) {
        throw "Generated VMF/layout pair is missing for $vmfName."
    }
    $layout = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($layout.vmfSha256 -ne $sourceHash) { throw "Generated layout is stale for $vmfName." }
    if ($layout.bounds.revision -ne 2 -or
        $layout.bounds.coastContactHalfExtent -ne $skyboxBase.cellBounds.coastContactHalfExtent -or
        $layout.bounds.visualHalfExtent -ne $skyboxBase.cellBounds.visualHalfExtent) {
        throw "Generated skyline bounds are stale for $vmfName."
    }

    $expectedSides = @($runtimeCell.waterSides | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $plannedSides = @($plannedCell.skyboxOceanSides | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $layoutSides = @($layout.waterSides | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($expectedSides -join ',') -cne ($plannedSides -join ',') -or
        ($expectedSides -join ',') -cne ($layoutSides -join ',')) {
        throw "Skyline coast sides differ from the runtime cell for logical cell $x,$y."
    }

    $previousGeometry = $skyboxBase.geometry.PSObject.Properties[$runtimeCell.map]
    $previousRecipeModels = $skyboxBase.recipes.PSObject.Properties[$runtimeCell.map]
    if ($null -eq $previousGeometry -or $null -eq $previousRecipeModels) {
        throw "The previous map has no skyline footprint/models to alias: $($runtimeCell.map)"
    }
    $previousSides = @($previousGeometry.Value.waterSides | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($previousSides -join ',') -cne ($expectedSides -join ',')) {
        throw "The previous skyline coast sides do not match logical cell $x,$y."
    }

    $mapHashes = @()
    foreach ($directory in @($buildPath, $contentMapsPath, $engineMapsPath)) {
        $bspPath = Join-Path $directory "$mapName.bsp"
        if (-not (Test-Path -LiteralPath $bspPath -PathType Leaf)) {
            throw "Compiled/staged map is missing: $bspPath"
        }
        $mapHashes += (Get-FileHash -LiteralPath $bspPath -Algorithm SHA256).Hash
    }
    if (@($mapHashes | Sort-Object -Unique).Count -ne 1) {
        throw "Build, content and engine BSP hashes disagree for $mapName."
    }

    $updatedById[$key].map = $mapName
    $updates.Add([pscustomobject]@{ id = $id; x = $x; y = $y; previous = $runtimeCell.map; map = $mapName })
    $skyboxUpdates.Add([pscustomobject]@{
        previous = $runtimeCell.map
        map = $mapName
        sourceHash = $sourceHash
        waterSides = @($layout.waterSides)
        coastHalfExtent = $layout.bounds.coastContactHalfExtent
        visualHalfExtent = $layout.bounds.visualHalfExtent
    })
}

foreach ($cell in $original.cells) {
    $updatedCell = $updatedById[[string]$cell.id]
    if ((Get-CellDataSignature $cell) -cne (Get-CellDataSignature $updatedCell)) {
        throw "Non-map runtime data changed for logical cell id $($cell.id)."
    }
}
if (($original.world | ConvertTo-Json -Depth 30 -Compress) -cne
    ($updated.world | ConvertTo-Json -Depth 30 -Compress)) {
    throw 'World profile/revision metadata changed during the map-name update.'
}

foreach ($update in $skyboxUpdates) {
    $newGeometry = [ordered]@{
        vmfSha256 = $update.sourceHash
        waterSides = @($update.waterSides)
        coastHalfExtent = $update.coastHalfExtent
        visualHalfExtent = $update.visualHalfExtent
    }
    Set-JsonProperty $skyboxUpdated.geometry $update.map $newGeometry
    Set-JsonProperty $skyboxUpdated.recipes $update.map $skyboxBase.recipes.PSObject.Properties[$update.previous].Value

    foreach ($section in @('snow', 'towers')) {
        $baseSection = $skyboxBase.PSObject.Properties[$section]
        $updatedSection = $skyboxUpdated.PSObject.Properties[$section]
        if ($null -ne $baseSection -and $null -ne $updatedSection) {
            $previousEntry = $baseSection.Value.PSObject.Properties[$update.previous]
            if ($null -ne $previousEntry) {
                Set-JsonProperty $updatedSection.Value $update.map $previousEntry.Value
            } else {
                Remove-JsonProperty $updatedSection.Value $update.map
            }
        }
    }

    $previousDetail = $skyboxBase.detail.recipes.PSObject.Properties[$update.previous]
    if ($null -ne $previousDetail) {
        Set-JsonProperty $skyboxUpdated.detail.recipes $update.map $previousDetail.Value
    } else {
        Remove-JsonProperty $skyboxUpdated.detail.recipes $update.map
    }
}

$outputDirectory = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
$skyboxOutputDirectory = Split-Path -Parent $skyboxOutputPath
if (-not (Test-Path -LiteralPath $skyboxOutputDirectory -PathType Container)) {
    [IO.Directory]::CreateDirectory($skyboxOutputDirectory) | Out-Null
}
# This targeted routing overlay preserves existing capture/skybox revision hashes; the later full-world export must refresh them.
$json = $updated | ConvertTo-Json -Depth 30 -Compress
[IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false))
$skyboxJson = $skyboxUpdated | ConvertTo-Json -Depth 30 -Compress
[IO.File]::WriteAllText($skyboxOutputPath, $skyboxJson, [Text.UTF8Encoding]::new($false))
Write-Output "Preview runtime map names and matching skyline footprints updated: $($updates.Count) cell(s); previous skyline models are reused until the later full-world export. Runtime output: $outputPath; skyline output: $skyboxOutputPath"
$updates | ForEach-Object {
    Write-Output "Cell $($_.x),$($_.y) (id $($_.id)): $($_.previous) -> $($_.map)"
}
