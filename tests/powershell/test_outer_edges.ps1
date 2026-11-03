param(
    [string]$OutputRoot = '',
    [string]$TemplateDirectory = '',
    [string]$TrustedMotorwayPlan = '',
    [switch]$UnitOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$projectRoot = $testsRepoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'generated\outer_edges' }
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
Import-Module (Join-Path $testsBinDirectory 'cell_bounds.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'outer_edges.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'skybox_models.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'transition_gates.psm1') -Force
$script:passed = 0

function Get-TestMotorwayGates {
    param($Layout)

    if ($null -eq $Layout.PSObject.Properties['motorwayAssembly'] -or $null -eq $Layout.motorwayAssembly) { return }
    $authority = $Layout.motorwayAssembly.PSObject.Properties['assemblyAuthority']
    $gates = @($Layout.motorwayAssembly.gates)
    if ($null -eq $authority -or $authority.Value -ne 'trusted_prior_approved_grid_layout' -or $gates.Count -eq 0) {
        throw "Trusted motorway contract has no approved gate records for $($Layout.cellTemplateFilename)."
    }
    return $gates
}

function Get-TestMotorwayGate {
    param($Layout, [string]$Direction)
    return @(Get-TestMotorwayGates $Layout | Where-Object { $_.direction -eq $Direction }) | Select-Object -First 1
}

function Get-TestGateTarget {
    param([object]$GateEntity)

    $match = [regex]::Match([string]$GateEntity.Get('targetname'), '^zm_transition_gate_(?<direction>[NESW])(?:_lane(?<lane>[12]))?$')
    if (-not $match.Success) { throw "Invalid transition gate target name: $($GateEntity.Get('targetname'))" }
    $laneIndex = if ($match.Groups['lane'].Success) { [int]$match.Groups['lane'].Value } else { $null }
    return [pscustomobject]@{ direction = $match.Groups['direction'].Value; laneIndex = $laneIndex }
}

function Get-TestExpectedGateCount {
    param([object]$Layout, [string[]]$Directions)

    $gates = @(Get-TestMotorwayGates $Layout | Where-Object { $null -ne $_ })
    if ($gates.Count -eq 0) {
        $count = 0
        foreach ($direction in $Directions) { $count++ }
        return $count
    }
    $count = 0
    foreach ($gate in $gates) {
        $route = if ($null -ne $gate.PSObject.Properties['route']) { [string]$gate.route } else { 'motorway' }
        if ($route -eq 'motorway' -and @($gate.lanes).Count -eq 2) {
            $count += 2
        } else {
            $count++
        }
    }
    return $count
}

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Outer edges: $Message" }
    $script:passed++
}

function Disable-TestFixtureMotorways {
    param([object]$Map)

    foreach ($cell in $Map.cells) {
        $cell.highway.present = $false
        $cell.highway.connections = @()
        $cell.highway.degree = 0
        $cell.highway.bridge = $false
        $cell.highway.bridgeCrossingDirection = $null
        $cell.highway.rampExits = @()
        $cell.highway.diagonal = $false
        $neighbors = $cell.PSObject.Properties['neighbors']
        if ($null -ne $neighbors) {
            foreach ($neighbor in @($neighbors.Value)) {
                $neighbor | Add-Member -NotePropertyName highwayConnected -NotePropertyValue $false -Force
            }
        }
    }
}

$resolved = & (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview
$settings = $resolved.Settings
if ([string]::IsNullOrWhiteSpace($TemplateDirectory)) {
    $TemplateDirectory = Join-Path $projectRoot $settings.paths.templateDirectory
}
$TemplateDirectory = (Resolve-Path -LiteralPath $TemplateDirectory).Path
if (-not $UnitOnly) {
    if ([string]::IsNullOrWhiteSpace($TrustedMotorwayPlan) -or
        -not (Test-Path -LiteralPath $TrustedMotorwayPlan -PathType Leaf)) {
        throw 'Pass the current approved full-world plan with -TrustedMotorwayPlan.'
    }
    $TrustedMotorwayPlan = (Resolve-Path -LiteralPath $TrustedMotorwayPlan).Path
}
$settings.paths.templateDirectory = [Uri]::UnescapeDataString(
    ([Uri]($projectRoot.TrimEnd('\') + '\')).MakeRelativeUri([Uri]($TemplateDirectory + '\')).ToString()
).Replace('/', '\')
$settings.vmfBuild.outerEdges.enabled = $true
$settingsPath = Join-Path $OutputRoot 'settings.json'
[IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$edgeSettings = $settings.vmfBuild.outerEdges
$roadHeight = Get-ZMTransitionDeckHeight (Join-Path $TemplateDirectory 'roads\tile_road.vmf') 640
$bridgeHeight = Get-ZMTransitionDeckHeight (Join-Path $TemplateDirectory 'roads\tile_road_bridge.vmf') 640
Assert ($roadHeight -eq 36 -and $bridgeHeight -eq 196) 'Gate elevation follows the actual road and bridge decks, not the ground/rails/supports.'
foreach ($expanded in @($false, $true)) {
    $gateBounds = Get-ZMCellBounds 5 640 $expanded
    foreach ($direction in @('N', 'E', 'S', 'W')) {
        $gate = Get-ZMTransitionGateCoordinates $gateBounds $direction 160
        $half = if ($expanded) { 2240 } else { 1600 }
        Assert ([Math]::Abs($gate.x) + [Math]::Abs($gate.y) -eq $half - 32) "$direction gate retains its 32-unit inset."
        Assert ($gate.zOffset -eq 160 -and $gate.arrivalZ -eq 200) "$direction bridge gate and arrival share the deck lift."
        Assert ($gate.yaw -eq @{ N = 90; E = 0; S = 270; W = 180 }[$direction]) "$direction gate faces outward."
        Assert ([Math]::Abs($gate.arrivalX) + [Math]::Abs($gate.arrivalY) -eq $half - $(if ($direction -eq 'N') { 128 } else { 64 })) "$direction arrival preserves its original side-specific inward inset."
    }
}
$fixedProps = @{
    'tile_edge_army_none.vmf' = @{
        'models/dogvsstrider/tree3_trunk.mdl' = 5
    }
    'tile_edge_ra_none.vmf' = @{
        'models/dogvsstrider/tree3_trunk.mdl' = 5
        'models/props_c17/signpole001.mdl' = 1
        'models/props_c17/streetsign004e.mdl' = 1
    }
    'tile_edge_ra_wall_1a.vmf' = @{
        'models/dogvsstrider/tree1_trunk.mdl' = 2
        'models/props_buildings/collapsedbuilding01awall.mdl' = 1
    }
    'tile_edge_ra_wall_1aa.vmf' = @{
        'models/props_c17/signpole001.mdl' = 1
        'models/props_c17/streetsign004e.mdl' = 1
        'models/props_buildings/collapsedbuilding02b.mdl' = 2
    }
}
foreach ($filename in $fixedProps.Keys) {
    $root = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw -LiteralPath (Join-Path $TemplateDirectory "edges\$filename")))
    $props = @($root.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'prop_dynamic_override' })
    foreach ($model in $fixedProps[$filename].Keys) {
        $count = @($props | Where-Object { $_.Get('model') -eq $model }).Count
        Assert ($count -ge $fixedProps[$filename][$model]) "$filename retains its approved dynamic $model props."
    }
    Assert (@($root.Children | Where-Object { $_.Get('classname') -eq 'prop_static' -and $_.Get('model') -match 'tree[13]_trunk|signpole001|streetsign004e' }).Count -eq 0) 'VBSP-incompatible new-edge static props must not reappear.'
}
$bounds = Get-ZMCellBounds 5 640 $true
Assert ($bounds.coreHalfExtent -eq 1600 -and $bounds.traversableHalfExtent -eq 2240 -and $bounds.visualHalfExtent -eq 2880 -and $bounds.neighbourPitch -eq 5760) 'Exact 5/7/9-tile extents and pitch.'
Assert ((Get-ZMCellBounds 5 640 $false).neighbourPitch -eq 4480) 'Legacy pitch must remain unchanged.'
$border = @(
    for ($y = -1; $y -le 5; $y++) {
        for ($x = -1; $x -le 5; $x++) {
            if ($x -in @(-1, 5) -or $y -in @(-1, 5)) { [pscustomobject]@{ tileX = $x; tileY = $y } }
        }
    }
)
$recipe = [pscustomobject]@{ environmentProfile = 'grassland'; placementSeed = 1337 }
$land = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
Assert ($land.Count -eq 32) 'Full outer ring must contain 32 slots.'
Assert (@($land | Where-Object { $_.tileX -gt -2 -and $_.tileX -lt 6 -and $_.tileY -gt -2 -and $_.tileY -lt 6 }).Count -eq 0) 'Only outer perimeter slots may be emitted.'
Assert (@($land | Group-Object { "$($_.tileX),$($_.tileY)" } | Where-Object Count -ne 1).Count -eq 0) 'Outer slots must be unique.'
$yawCases = @(@(-2, 2, 270), @(6, 2, 90), @(2, -2, 180), @(2, 6, 0), @(-2, -2, 180), @(6, -2, 90), @(6, 6, 0), @(-2, 6, 270))
foreach ($case in $yawCases) {
    $piece = @($land | Where-Object { $_.tileX -eq $case[0] -and $_.tileY -eq $case[1] })
    Assert ($piece.Count -eq 1 -and $piece[0].rotationYaw -eq $case[2]) "Facing $($case[0]),$($case[1])."
}
$second = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
Assert (($land | ConvertTo-Json -Depth 5) -ceq ($second | ConvertTo-Json -Depth 5)) 'Placement must be deterministic.'
$entranceBorder = @($border | Where-Object { -not ($_.tileX -eq 5 -and $_.tileY -in @(1, 2, 3)) })
$entranceRecipe = [pscustomobject]@{
    environmentProfile = 'grassland'
    placementSeed = 1337
    safeZoneEntrance = [pscustomobject]@{ slot = 'E' }
    suppressedBorderTiles = @(1..3 | ForEach-Object { [pscustomobject]@{ tileX = 5; tileY = $_ } })
}
$entranceOuter = @(Get-ZMOuterEdgePlacements $entranceRecipe 5 $edgeSettings $entranceBorder @{} @{})
$entranceBackfill = @($entranceOuter | Where-Object { $_.tileX -eq 6 -and $_.tileY -in @(1, 2, 3) })
Assert ($entranceBackfill.Count -eq 3 -and @($entranceBackfill | Where-Object { $_.targetname -notlike 'zm_outer_wall_*' }).Count -eq 0) 'Land outer-edge slots behind a suppressed east safe-zone entrance must be filled.'
$missingBorderRecipe = [pscustomobject]@{ environmentProfile = 'grassland'; placementSeed = 1337 }
$missingBorderOuter = @(Get-ZMOuterEdgePlacements $missingBorderRecipe 5 $edgeSettings $entranceBorder @{} @{})
Assert (@($missingBorderOuter | Where-Object { $_.tileX -eq 6 -and $_.tileY -in @(1, 2, 3) }).Count -eq 0) 'Missing border slots without a safe-zone entrance remain omitted.'
$destroyedWalls = @($edgeSettings.profileTemplates['destroyed'].wallVariationTemplates)
Assert ($destroyedWalls.Count -gt 0 -and @($destroyedWalls | Where-Object { $_ -notmatch '^edges/tile_edge_destroyed_' }).Count -eq 0) 'Destroyed outer edges use the authored destroyed pool, not the radioactive pool.'
foreach ($tier in @('2', '3')) {
    Assert ($edgeSettings.profileTemplates['destroyed'].wallDensityFallbacks[$tier] -in $destroyedWalls) "Destroyed outer tier $tier has a fallback within its authored pool."
}
foreach ($profile in @('radioactive', 'destroyed', 'military', 'fortified')) {
    $recipe.environmentProfile = $profile
    $pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{})
    $pool = @($edgeSettings.profileTemplates[$profile].wallVariationTemplates)
    $profileSettings = $edgeSettings.profileTemplates[$profile]
    $expectedCorners = @($edgeSettings.cornerVariationTemplates)
    if ($profileSettings.ContainsKey('cornerTemplate') -and -not [string]::IsNullOrWhiteSpace($profileSettings.cornerTemplate)) {
        $expectedCorners = @([string]$profileSettings.cornerTemplate)
    }
    if ($profileSettings.ContainsKey('cornerVariationTemplates') -and @($profileSettings.cornerVariationTemplates).Count -gt 0) {
        $expectedCorners = @($profileSettings.cornerVariationTemplates | ForEach-Object { [string]$_ })
    }
    foreach ($piece in $pieces) {
        Assert ($(if ($piece.targetname -like 'zm_outer_corner_*') { $piece.template -in $expectedCorners } else { $piece.template -in $pool })) "$profile uses its wall pool and the correct profile/default corner pool."
    }
}
# Corners come from the density-aware default variation pool; a profile cornerTemplate overrides it.
$recipe.environmentProfile = 'grassland'
$cornerPieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{} @{} | Where-Object { $_.targetname -like 'zm_outer_corner_*' })
Assert ($cornerPieces.Count -eq 4) 'Four outer corners.'
foreach ($piece in $cornerPieces) { Assert ($piece.template -in @($edgeSettings.cornerVariationTemplates)) 'Default corner comes from cornerVariationTemplates.' }
$overrideSettings = $edgeSettings.Clone()
$overrideSettings.profileTemplates = @{ grassland = @{ wallVariationTemplates = @($edgeSettings.wallVariationTemplates); cornerTemplate = 'edges/tile_edge_wall_corner_1aa.vmf' } }
foreach ($piece in @(Get-ZMOuterEdgePlacements $recipe 5 $overrideSettings $border @{} @{} | Where-Object { $_.targetname -like 'zm_outer_corner_*' })) {
    Assert ($piece.template -eq 'edges/tile_edge_wall_corner_1aa.vmf') 'Profile cornerTemplate overrides the default corner variations.'
}
# Industrial-majority cells use the industrial wall pool unless their own profile has one.
$industrialProfiles = @{ industrial = @{}; radioactive = @{} }
$mostlyIndustrial = [pscustomobject]@{ environmentProfile = 'grassland'; tilePlacements = @(
    [pscustomobject]@{ template = 'buildings/tile_industrial_1a.vmf' },
    [pscustomobject]@{ template = 'buildings/tile_warehouse_1aa.vmf' },
    [pscustomobject]@{ template = 'buildings/tile_building_1a.vmf' },
    [pscustomobject]@{ template = 'roads/tile_road.vmf' }) }
Assert ((Get-ZMWallProfileKey $mostlyIndustrial $industrialProfiles) -eq 'industrial') 'Industry-majority cell selects the industrial wall profile.'
$mostlyResidential = [pscustomobject]@{ environmentProfile = 'grassland'; tilePlacements = @(
    [pscustomobject]@{ template = 'buildings/tile_industrial_1a.vmf' },
    [pscustomobject]@{ template = 'buildings/tile_building_1a.vmf' }) }
Assert ((Get-ZMWallProfileKey $mostlyResidential $industrialProfiles) -eq 'grassland') 'An industry half (not majority) keeps the cell profile.'
$mostlyIndustrial.environmentProfile = 'radioactive'
Assert ((Get-ZMWallProfileKey $mostlyIndustrial $industrialProfiles) -eq 'radioactive') 'A profile with its own pool outranks the industrial majority.'
Assert ((Get-ZMWallProfileKey ([pscustomobject]@{ environmentProfile = 'grassland' }) $industrialProfiles) -eq 'grassland') 'Recipes without placements keep their profile.'
$industrialSetting = $edgeSettings.profileTemplates['industrial']
Assert ($null -ne $industrialSetting -and @($industrialSetting.wallVariationTemplates).Count -gt 0) 'Settings define an industrial outer-edge pool.'
$recipe.environmentProfile = 'grassland'
# Legacy omission behaviour remains the contract whenever no authored ocean pieces are configured.
$legacyEdgeSettings = $edgeSettings.Clone()
$legacyEdgeSettings.Remove('oceanTemplates')
foreach ($mask in 0..15) {
    $water = @{}
    $sides = @('N', 'E', 'S', 'W')
    for ($i = 0; $i -lt 4; $i++) { if ($mask -band (1 -shl $i)) { $water[$sides[$i]] = $true } }
    $pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $legacyEdgeSettings $border $water @{})
    foreach ($piece in $pieces) {
        Assert (-not (($piece.tileY -eq -2 -and $water.ContainsKey('N')) -or ($piece.tileX -eq 6 -and $water.ContainsKey('E')) -or ($piece.tileY -eq 6 -and $water.ContainsKey('S')) -or ($piece.tileX -eq -2 -and $water.ContainsKey('W')))) "Water mask $mask must omit side fill and mixed corners."
    }
    $expected = @($land | Where-Object {
        -not (($_.tileY -eq -2 -and $water.ContainsKey('N')) -or ($_.tileX -eq 6 -and $water.ContainsKey('E')) -or ($_.tileY -eq 6 -and $water.ContainsKey('S')) -or ($_.tileX -eq -2 -and $water.ContainsKey('W')))
    }).Count
    Assert ($pieces.Count -eq $expected) "Water mask $mask exact count."
}
$corridor = @(Get-ZMOuterEdgePlacements $recipe 5 $legacyEdgeSettings $border @{ N = $true; W = $true } @{ N = 'roads\tile_road_straight.vmf' })
Assert (@($corridor | Where-Object { $_.tileY -eq -2 }).Count -eq 1 -and @($corridor | Where-Object { $_.tileY -eq -2 })[0].tileX -eq 2) 'Only a reserved centre corridor may continue across a waterfront side.'

$oceanPool = @(Get-ZMOuterEdgeOceanTemplates $edgeSettings)
Assert ($oceanPool.Count -eq 15 -and @($oceanPool | Where-Object { $_ -notmatch '^edges/tile_edge_ocean_([1-9]|1[0-5])a\.vmf$' }).Count -eq 0 -and @($oceanPool | Where-Object { -not (Test-Path -LiteralPath (Join-Path $TemplateDirectory $_)) }).Count -eq 0) 'Preview settings provide the single 1a-15a ocean pool, flat pieces included, all authored.'
foreach ($template in $oceanPool) { Assert (Test-Path -LiteralPath (Join-Path $TemplateDirectory $template) -PathType Leaf) "$template exists." }
Assert (@(Get-ZMOuterEdgeOceanTemplates $legacyEdgeSettings).Count -eq 0) 'Absent oceanTemplates keeps the legacy omission path.'
$oceanYaws = @{ N = 0; E = 270; S = 180; W = 90 }
foreach ($oceanSide in @('N', 'E', 'S', 'W')) {
    $pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{ $oceanSide = $true } @{})
    Assert ($pieces.Count -eq 32) "$oceanSide ocean side fills every outer slot, including both adjoining corners."
    $sideSlot = { param($p) switch ($oceanSide) { N { $p.tileY -eq -2 }; S { $p.tileY -eq 6 }; E { $p.tileX -eq 6 }; W { $p.tileX -eq -2 } } }
    $oceanPieces = @($pieces | Where-Object { & $sideSlot $_ })
    Assert ($oceanPieces.Count -eq 9) "$oceanSide ocean side spans seven edge slots plus two corners."
    foreach ($piece in $oceanPieces) {
        Assert ($piece.template -in $oceanPool -and $piece.targetname -like 'zm_outer_ocean_*') "$oceanSide ocean slot $($piece.tileX),$($piece.tileY) uses an ocean piece."
        Assert ($piece.rotationYaw -eq $oceanYaws[$oceanSide]) "$oceanSide ocean slot $($piece.tileX),$($piece.tileY) turns canonical +Y sea outward."
    }
    $landPieces = @($pieces | Where-Object { -not (& $sideSlot $_) })
    $landBaseline = @($land | Where-Object { -not (& $sideSlot $_) })
    Assert (($landPieces | ConvertTo-Json -Depth 5) -ceq ($landBaseline | ConvertTo-Json -Depth 5)) "$oceanSide ocean pieces leave land-facing walls and corners unchanged."
}
$westOcean = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{ W = $true } @{})
Assert (($westOcean | ConvertTo-Json -Depth 5) -ceq (@(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{ W = $true } @{}) | ConvertTo-Json -Depth 5)) 'Ocean selection is deterministic.'
Assert (@($westOcean | Where-Object { $_.tileX -eq -2 } | ForEach-Object { $_.template } | Sort-Object -Unique).Count -gt 1) 'Ocean selection varies along the coast.'
$oceanRoute = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $border @{ W = $true } @{ W = 'roads\tile_road.vmf' })
$routeSlot = @($oceanRoute | Where-Object { $_.tileX -eq -2 -and $_.tileY -eq 2 })
Assert ($routeSlot.Count -eq 1 -and $routeSlot[0].template -eq 'roads\tile_road.vmf') 'A reserved route still continues through an ocean side.'
$oceanSuppressed = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings @($border | Where-Object { -not ($_.tileX -eq -1 -and $_.tileY -eq 1) }) @{ W = $true } @{})
$suppressedOcean = @($oceanSuppressed | Where-Object { $_.tileX -eq -2 -and $_.tileY -eq 1 })
Assert ($suppressedOcean.Count -eq 1 -and $suppressedOcean[0].template -in $oceanPool -and $suppressedOcean[0].rotationYaw -eq 90) 'An authored entrance ending at the traversable edge still receives its ocean coast piece.'
$landEntranceRecipe = [pscustomobject]@{
    environmentProfile = 'grassland'
    placementSeed = 1337
    safeZoneEntrance = [pscustomobject]@{ slot = 'E' }
    suppressedBorderTiles = @([pscustomobject]@{ tileX = 5; tileY = 1 })
}
$landSuppressed = @(Get-ZMOuterEdgePlacements $landEntranceRecipe 5 $edgeSettings @($border | Where-Object { -not ($_.tileX -eq 5 -and $_.tileY -eq 1) }) @{ W = $true } @{})
$landBackfill = @($landSuppressed | Where-Object { $_.tileX -eq 6 -and $_.tileY -eq 1 })
Assert ($landBackfill.Count -eq 1 -and $landBackfill[0].targetname -like 'zm_outer_wall_*') 'A land-facing slot behind an entrance on an ocean-border cell remains filled.'
$oceanBounds = Get-ZMCellBounds 5 640 $true $true
Assert ($oceanBounds.coastContactHalfExtent -eq 2880 -and $oceanBounds.revision -eq 2 -and $oceanBounds.neighbourPitch -eq 5760) 'Ocean pieces move the skybox coast contact to the visual edge without changing pitch.'
Assert ($bounds.coastContactHalfExtent -eq 2240) 'Without ocean pieces the beach still meets the original border.'
$threw = $false
try { Get-ZMCellBounds 5 640 $false $true | Out-Null } catch { $threw = $true }
Assert $threw 'Ocean pieces require the outer ring.'
Assert (Test-ZMOceanEdgesEnabled @{ enabled = $true; oceanTemplates = @('edges/tile_edge_ocean_1a.vmf') }) 'Enabled outer edges with ocean templates enable ocean edges.'
Assert (-not (Test-ZMOceanEdgesEnabled @{ enabled = $false; oceanTemplates = @('edges/tile_edge_ocean_1a.vmf') })) 'Disabled outer edges disable ocean edges.'
Assert (-not (Test-ZMOceanEdgesEnabled $legacyEdgeSettings)) 'Missing ocean templates disable ocean edges.'
$suppressed = @($border | Where-Object { -not ($_.tileY -eq -1 -and $_.tileX -eq 2) })
$pieces = @(Get-ZMOuterEdgePlacements $recipe 5 $edgeSettings $suppressed @{} @{ N = 'road.vmf' })
Assert (@($pieces | Where-Object { $_.tileY -eq -2 -and $_.tileX -eq 2 }).Count -eq 0) 'Entrance suppression precedes route reservation.'
$routeBorder = @(
    [ordered]@{ tileX = 5; tileY = 2; template = 'roads\tile_road_bridge.vmf'; targetname = 'zm_transition_road_E' },
    [ordered]@{ tileX = -1; tileY = 2; template = 'roads\tile_road_bridge.vmf'; targetname = 'zm_border_W_-1_2' },
    [ordered]@{ tileX = 2; tileY = -1; template = 'roads\tile_road_gate_a.vmf'; targetname = 'zm_transition_road_N' },
    [ordered]@{ tileX = 2; tileY = 5; template = 'roads\tile_motorway.vmf'; targetname = 'zm_border_S_2_5' },
    [ordered]@{ tileX = 0; tileY = 5; template = 'border\tile_border_wall.vmf'; targetname = 'zm_border_S_0_5' }
)
$routes = Get-ZMOuterEdgeRoadTemplates $routeBorder 5 'roads\tile_road.vmf' 'roads\tile_motorway.vmf' 'roads\tile_road_bridge.vmf'
Assert ($routes['E'] -eq 'roads\tile_road_bridge.vmf' -and $routes['W'] -eq 'roads\tile_road_bridge.vmf') 'Bridge corridors continue as elevated deck even on transition/ramp-exit sides.'
Assert ($routes['N'] -eq 'roads\tile_road.vmf') 'Gate-road variants still flatten to the plain straight road.'
Assert ($routes['S'] -eq 'roads\tile_motorway.vmf' -and $routes.Count -eq 4) 'Motorway corridors are unchanged and walls do not reserve routes.'

$source = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'celltemplates\template_border_s.vmf')
$expanded = Expand-ZMOuterEdgeShell $source $bounds
$parsed = [ZombieSim.Skybox.KeyValuesParser]::Parse($expanded)
Assert ($null -ne $parsed.Child('cameras')) 'Expanded shell retains editor sections.'
foreach ($solid in $parsed.Child('world').Children | Where-Object Name -eq 'solid') {
    $material = ($solid.Children | Where-Object Name -eq 'side' | Select-Object -First 1).Get('material').ToUpperInvariant()
    $vertices = @($solid.Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Child('vertices_plus').GetAll('v') })
    $axes = @()
    foreach ($axis in 0..1) { $axes += ,@($vertices | ForEach-Object { [double]($_ -split '\s+')[$axis] } | Sort-Object -Unique) }
    if ($material -eq 'TOOLS/TOOLSCLIP') {
        foreach ($axis in $axes) { foreach ($value in $axis) { Assert ([Math]::Abs($value) -in @(2240, 2304)) 'Clip perimeter must release the existing border and exclude the new scenery ring.' } }
    } elseif ($material -eq 'TOOLS/TOOLSSKYBOX') {
        foreach ($axis in $axes) { foreach ($value in $axis) { Assert ([Math]::Abs($value) -in @(2880, 2944)) 'Sky seals close exactly at the 2880 visual bound so the neighbour skybox meets the outer ring without a black strip.' } }
    }
}

$shellSides = @('W', 'E', 'S', 'N')
foreach ($mask in 0..15) {
    $ocean = @{}
    for ($i = 0; $i -lt 4; $i++) { if ($mask -band (1 -shl $i)) { $ocean[$shellSides[$i]] = $true } }
    $shell = [ZombieSim.Skybox.KeyValuesParser]::Parse((Expand-ZMOuterEdgeShell $source $bounds $ocean))
    foreach ($solid in $shell.Child('world').Children | Where-Object Name -eq 'solid') {
        $material = ($solid.Children | Where-Object Name -eq 'side' | Select-Object -First 1).Get('material').ToUpperInvariant()
        $vertices = @($solid.Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Child('vertices_plus').GetAll('v') })
        foreach ($axis in 0..1) {
            foreach ($value in @($vertices | ForEach-Object { [double]($_ -split '\s+')[$axis] } | Sort-Object -Unique)) {
                $side = $shellSides[$axis * 2 + $(if ($value -lt 0) { 0 } else { 1 })]
                $allowed = if ($material -eq 'TOOLS/TOOLSCLIP') { @(2240, 2304) } elseif ($ocean.ContainsKey($side)) { @(2240, 2304) } else { @(2880, 2944) }
                Assert ([Math]::Abs($value) -in $allowed) "Shell mask $mask keeps floor/sky at the original ocean border and expands only land-facing sides; clips unchanged."
            }
        }
    }
}

if ($UnitOnly) {
    Write-Output "Outer-edge unit checks: $script:passed assertions passed; full-plan and runtime fixtures not run."
    return
}

$planPath = Join-Path $OutputRoot 'plan.json'
$listPath = Join-Path $OutputRoot 'required.txt'
$cellDirectory = Join-Path $OutputRoot 'src'
$fixtureMap = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'border_showcase_fixture_map.json') | ConvertFrom-Json
# Normal motorways are covered later with the current trusted plan; this synthetic fixture has no matching trust plan.
Disable-TestFixtureMotorways $fixtureMap
$fixtureMapPath = Join-Path $OutputRoot 'border-showcase-map.json'
[IO.File]::WriteAllText($fixtureMapPath, ($fixtureMap | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $fixtureMapPath -CellDirectory $cellDirectory -Output $planPath -ListOutput $listPath | Out-Null
if (-not $?) { throw 'Expanded fixture planner failed.' }
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
Assert (@($plan.cells | Where-Object { $_.x -eq 0 -and (@($_.skyboxOceanSides) -join ',') -ne 'W' }).Count -eq 0) 'West boundary cells omit only the skybox ocean side.'
Assert (@($plan.cells | Where-Object { $_.x -gt 0 -and @($_.skyboxOceanSides).Count -gt 0 }).Count -eq 0) 'Authored water corners do not change outer-edge omission policy.'
$expandedRecipeNames = @($plan.cells | ForEach-Object { [string]$_.cellTemplateFilename })
Assert (@($expandedRecipeNames | Where-Object { $_ -match '-edge2\.vmf$' }).Count -eq 0) 'Expanded maps must not retain the retired test-only edge2 suffix.'
$sharedRecipeConflicts = @($plan.cells | Group-Object cellTemplateFilename | Where-Object {
    @($_.Group | ForEach-Object { ConvertTo-Json -InputObject $_.tilePlacements -Depth 40 -Compress } | Sort-Object -Unique).Count -gt 1
})
Assert ($sharedRecipeConflicts.Count -eq 0) 'Cells sharing a recipe filename must have identical core placements.'
Assert (@($expandedRecipeNames | Where-Object { $_ -match '-oceanw\.vmf$' }).Count -gt 0) 'West-ocean recipe identity remains in the active filename.'
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory $cellDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Expanded fixture builder failed.' }
foreach ($group in $plan.cells | Group-Object cellTemplateFilename) {
    $vmfPath = Join-Path $cellDirectory $group.Name
    $layout = Get-Content -Raw -LiteralPath ([IO.Path]::ChangeExtension($vmfPath, '.layout.json')) | ConvertFrom-Json
    $cell = $group.Group[0]
    $text = Get-Content -Raw -LiteralPath $vmfPath
    Assert ($layout.vmfSha256 -eq (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Layout must identify the exact current VMF.'
    Assert ([regex]::Matches($text, '"targetname" "zm_outer_').Count -eq @($layout.outerPlacements).Count) 'VMF and artwork placement metadata must agree.'
    Assert ([regex]::Matches($text, '"targetname" "(?:zm_border_|zm_transition_road_)').Count -eq @($layout.borderPlacements).Count) 'Original border remains independent of outer-ring count.'
    $gateDirections = if ($null -ne $cell.PSObject.Properties['gateDirections']) { @($cell.gateDirections) } else { @($cell.activeEntrances) }
    $expectedGateCount = Get-TestExpectedGateCount $layout $gateDirections
    Assert ([regex]::Matches($text, '"zm_transition_gate" "1"').Count -eq $expectedGateCount) 'Each motorway route emits one trigger per carriageway; ordinary routes retain one.'
    $vmf = [ZombieSim.Skybox.KeyValuesParser]::Parse($text)
    foreach ($gateEntity in @($vmf.Children | Where-Object { $_.Get('zm_transition_gate') -eq '1' })) {
        $target = Get-TestGateTarget $gateEntity
        $code = $target.direction
        $motorwayGate = Get-TestMotorwayGate $layout $code
        if ($null -ne $motorwayGate) {
            Assert ($gateEntity.Get('origin') -eq ('{0} {1} {2}' -f $motorwayGate.x, $motorwayGate.y, ($motorwayGate.deckZ + 20))) "$($group.Name) $code trigger matches its planned gate contract."
            $route = if ($null -ne $motorwayGate.PSObject.Properties['route']) { [string]$motorwayGate.route } else { 'motorway' }
            if ($route -ne 'road') {
                Assert ($null -ne $target.laneIndex -and $gateEntity.Get('zm_transition_lane') -eq [string]$target.laneIndex) "$($group.Name) $code trigger identifies its carriageway."
            } else {
                Assert ($null -eq $target.laneIndex) "$($group.Name) ordinary-road trigger remains combined."
            }
            $arrivalLane = $motorwayGate.lanes[$motorwayGate.arrivalLane - 1]
            $landmark = @($vmf.Children | Where-Object { $_.Get('targetname') -eq "$($gateEntity.Get('zm_transition_direction').ToUpperInvariant())_ENTRANCE" })
            Assert ($landmark.Count -eq 1 -and $landmark[0].Get('origin') -eq ('{0} {1} {2}' -f $arrivalLane.arrivalX, $arrivalLane.arrivalY, ($motorwayGate.deckZ + 4))) "$($group.Name) $code arrival uses its planned lane."
            continue
        }
        if ($null -ne $target.laneIndex) { throw "Ordinary transition gate unexpectedly has a lane tag: $($group.Name) $code" }
        $slot = @($layout.borderPlacements | Where-Object {
            $borderPiece = $_
            $onSide = switch ($code) { N { $borderPiece.tileY -eq -1 }; S { $borderPiece.tileY -eq 5 }; E { $borderPiece.tileX -eq 5 }; W { $borderPiece.tileX -eq -1 } }
            $borderPiece.targetname -eq "zm_transition_road_$code" -or
                ($borderPiece.template -eq $settings.cellPlanning.transportTemplates.bridgeRoad -and $onSide)
        })
        $lift = if (@($slot | Where-Object { $_.template -eq $settings.cellPlanning.transportTemplates.bridgeRoad }).Count -gt 0) { 160 } else { 0 }
        $expected = Get-ZMTransitionGateCoordinates $layout.bounds $code $lift
        Assert ($gateEntity.Get('origin') -eq ('{0} {1} {2}' -f $expected.x, $expected.y, (56 + $lift))) "$($group.Name) $code trigger is at the expanded boundary and correct deck height."
        $landmark = @($vmf.Children | Where-Object { $_.Get('targetname') -eq "$($gateEntity.Get('zm_transition_direction').ToUpperInvariant())_ENTRANCE" })
        Assert ($landmark.Count -eq 1 -and $landmark[0].Get('origin') -eq ('{0} {1} {2}' -f $expected.arrivalX, $expected.arrivalY, $expected.arrivalZ)) "$($group.Name) $code arrival is on the same deck inside the gate."
        foreach ($prop in @($vmf.Children | Where-Object { $_.Get('targetname') -like "zm_transition_gate_$code`_barricade_*" })) {
            $z = [double](($prop.Get('origin') -split ' ')[2])
            Assert ($z -ge 42 + $lift -and $z -le 44 + $lift) 'Barricade props share the gate deck lift.'
        }
    }
    foreach ($bridgeSlot in @($layout.borderPlacements | Where-Object { $_.template -like '*tile_road_bridge.vmf' })) {
        $outerX = if ($bridgeSlot.tileX -eq -1) { -2 } elseif ($bridgeSlot.tileX -eq 5) { 6 } else { $bridgeSlot.tileX }
        $outerY = if ($bridgeSlot.tileY -eq -1) { -2 } elseif ($bridgeSlot.tileY -eq 5) { 6 } else { $bridgeSlot.tileY }
        $outer = @($layout.outerPlacements | Where-Object { $_.tileX -eq $outerX -and $_.tileY -eq $outerY })
        Assert ($outer.Count -eq 1 -and $outer[0].template -eq $bridgeSlot.template) "$($group.Name) continues its bridge deck into the outer ring at $outerX,$outerY."
    }
}
$before = @{}
foreach ($path in Get-ChildItem -LiteralPath $cellDirectory -Filter '*.vmf') { $before[$path.Name] = $path.LastWriteTimeUtc }
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory $cellDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Incremental expanded fixture builder failed.' }
foreach ($path in Get-ChildItem -LiteralPath $cellDirectory -Filter '*.vmf') { Assert ($path.LastWriteTimeUtc -eq $before[$path.Name]) 'Unchanged recipes must retain timestamps.' }

$runtimePath = Join-Path $OutputRoot 'runtime.json'
$runtimeMap = Get-Content -Raw -LiteralPath (Join-Path $testsBinDirectory 'preview_grid_24x24_seed_1337.json') | ConvertFrom-Json
$runtimeMap.cells = @($runtimeMap.cells | Where-Object { $_.x -lt 6 -and $_.y -ge 9 -and $_.y -lt 15 })
$runtimeMap.safeZones = @($runtimeMap.safeZones | Where-Object { $_.x -lt 6 -and $_.y -ge 9 -and $_.y -lt 15 })
foreach ($cell in $runtimeMap.cells) {
    $cell.y -= 9
    $cell.metro.lines = @()
    $cell.metro.stop = $null
    foreach ($neighbor in $cell.neighbors) {
        $neighbor.y -= 9
        $neighbor.inBounds = $neighbor.x -ge 0 -and $neighbor.x -lt 6 -and $neighbor.y -ge 0 -and $neighbor.y -lt 6
        if (-not $neighbor.inBounds) { $neighbor.roadConnected = $false; $neighbor.highwayConnected = $false }
    }
    $inside = @($cell.neighbors | Where-Object inBounds | ForEach-Object { $_.direction })
    $cell.road.connections = @($cell.road.connections | Where-Object { $_ -in $inside })
    $cell.road.degree = $cell.road.connections.Count
    $cell.highway.connections = @($cell.highway.connections | Where-Object { $_ -in $inside })
    $cell.highway.degree = $cell.highway.connections.Count
}
foreach ($zone in $runtimeMap.safeZones) { $zone.y -= 9 }
$runtimeMap.map.gridCells = 6
$runtimeMap.map.width = 384
$runtimeMap.map.height = 384
$runtimeMap.map.origin.cellY = 3
$runtimeMapPath = Join-Path $OutputRoot 'runtime-map.json'
$runtimePlanPath = Join-Path $OutputRoot 'runtime-plan.json'
$runtimeSources = Join-Path $OutputRoot 'runtime-src'
[IO.File]::WriteAllText($runtimeMapPath, ($runtimeMap | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($false))
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $runtimeMapPath -CellDirectory $runtimeSources -Output $runtimePlanPath -ListOutput (Join-Path $OutputRoot 'runtime-required.txt') | Out-Null
if (-not $?) { throw 'Isolated origin fixture planning failed.' }
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $runtimePlanPath -CellDirectory $runtimeSources -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Isolated origin fixture generation failed.' }
& (Join-Path $testsBinDirectory 'export_runtime_world_data.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $runtimeMapPath -PlanData $runtimePlanPath -Output $runtimePath | Out-Null
if (-not $?) { throw 'Expanded runtime metadata export failed.' }
$runtime = Get-Content -Raw -LiteralPath $runtimePath | ConvertFrom-Json
Assert ($runtime.world.cellBounds.neighbourPitch -eq 5760 -and $runtime.world.cellBounds.coreHalfExtent -eq 1600) 'Runtime distinguishes visual pitch from core eligibility.'
Assert (@($runtime.cells | Where-Object { $null -eq $_.PSObject.Properties['waterSides'] }).Count -eq 0) 'Runtime explicitly retains per-cell coast classification.'

# Exercise protected real-world recipes without touching their installed outputs.
$coverageDirectory = Join-Path $OutputRoot 'coverage'
$coveragePlanPath = Join-Path $OutputRoot 'coverage-plan.json'
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData (Join-Path $testsBinDirectory 'preview_grid_24x24_seed_1337.json') -CellDirectory $coverageDirectory -Output $coveragePlanPath -ListOutput (Join-Path $OutputRoot 'coverage-required.txt') -TrustedMotorwayPlan $TrustedMotorwayPlan | Out-Null
if (-not $?) { throw 'Expanded protected recipe planning failed.' }
$coveragePlan = Get-Content -Raw -LiteralPath $coveragePlanPath | ConvertFrom-Json
# The Alpha 3.1.5 legacy-policy comparisons are retired: Alpha 3.2 density zoning intentionally changes
# recipe content, and normal wide motorways mean the planner refuses to re-plan this grid without the
# expanded rings. Expanded-only Storm Drain invariants below remain protected.
$selected = @($coveragePlan.cells | Where-Object {
    $_.safeZoneEntrance -ne $null -or $_.environmentProfile -in @('radioactive', 'fortified') -or $_.transportFeature -like 'bridge-*'
} | Group-Object { if ($_.transportFeature -like 'bridge-*') { $_.transportFeature } elseif ($_.safeZoneEntrance) { "entrance-$($_.safeZoneEntrance.mode)" } else { $_.environmentProfile } } | ForEach-Object { $_.Group[0] })
$storm = @($coveragePlan.cells | Where-Object { $_.x -eq 0 -and $_.y -eq 12 })
$reportedBridge = @($coveragePlan.cells | Where-Object { $_.x -eq 15 -and $_.y -eq 17 })
Assert ($reportedBridge.Count -eq 1 -and $reportedBridge[0].transportFeature -like 'bridge-*') 'Exact reported bridge logical15,5 is included.'
$selected = @(@($selected) + $storm + $reportedBridge | Group-Object cellTemplateFilename | ForEach-Object { $_.Group[0] })
$coveragePlan.cells = $selected
$coveragePlan.safeZoneMaps = @()
[IO.File]::WriteAllText($coveragePlanPath, ($coveragePlan | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'coverage-required.txt'), [string[]]@($selected | ForEach-Object { $_.cellTemplateFilename }), [Text.UTF8Encoding]::new($false))
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $coveragePlanPath -CellDirectory $coverageDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Protected expanded recipe builder failed.' }
foreach ($cell in $selected) {
    $layout = Get-Content -Raw -LiteralPath (Join-Path $coverageDirectory ([IO.Path]::ChangeExtension($cell.cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
    $borderLeaseKeys = @()
    if ($null -ne $layout.PSObject.Properties['motorwayAssembly'] -and $null -ne $layout.motorwayAssembly.PSObject.Properties['leases']) {
        $borderLeaseKeys = @($layout.motorwayAssembly.leases | Where-Object ring -eq 'border' | ForEach-Object { "$($_.tileX),$($_.tileY)" } | Sort-Object -Unique)
    }
    Assert (@($layout.borderPlacements | Where-Object { "$($_.tileX),$($_.tileY)" -in $borderLeaseKeys }).Count -eq 0) 'Wide motorway border leases never overlap an emitted border piece.'
    Assert (@($layout.borderPlacements).Count -eq 24 - @($cell.suppressedBorderTiles).Count - $borderLeaseKeys.Count) 'Protected entrance border suppression remains unchanged.'
    $entities = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw (Join-Path $coverageDirectory $cell.cellTemplateFilename))).Children
    foreach ($gateEntity in @($entities | Where-Object { $_.Get('zm_transition_gate') -eq '1' })) {
        $target = Get-TestGateTarget $gateEntity
        $code = $target.direction
        $motorwayGate = Get-TestMotorwayGate $layout $code
        if ($null -ne $motorwayGate) {
            Assert ($gateEntity.Get('origin') -eq ('{0} {1} {2}' -f $motorwayGate.x, $motorwayGate.y, ($motorwayGate.deckZ + 20))) "$($cell.cellTemplateFilename) $code trigger matches its planned gate contract."
            $route = if ($null -ne $motorwayGate.PSObject.Properties['route']) { [string]$motorwayGate.route } else { 'motorway' }
            if ($route -ne 'road') {
                Assert ($null -ne $target.laneIndex -and $gateEntity.Get('zm_transition_lane') -eq [string]$target.laneIndex) "$($cell.cellTemplateFilename) $code trigger identifies its carriageway."
            } else {
                Assert ($null -eq $target.laneIndex) "$($cell.cellTemplateFilename) ordinary-road trigger remains combined."
            }
            $arrivalLane = $motorwayGate.lanes[$motorwayGate.arrivalLane - 1]
            $landmark = @($entities | Where-Object { $_.Get('targetname') -eq "$($gateEntity.Get('zm_transition_direction').ToUpperInvariant())_ENTRANCE" })
            Assert ($landmark.Count -eq 1 -and $landmark[0].Get('origin') -eq ('{0} {1} {2}' -f $arrivalLane.arrivalX, $arrivalLane.arrivalY, ($motorwayGate.deckZ + 4))) "$($cell.cellTemplateFilename) $code arrival uses its planned lane."
            continue
        }
        if ($null -ne $target.laneIndex) { throw "Ordinary transition gate unexpectedly has a lane tag: $($cell.cellTemplateFilename) $code" }
        $bridgeSide = switch ($cell.transportFeature) {
            'bridge-horizontal' { $code -in @('E', 'W') }
            'bridge-vertical' { $code -in @('N', 'S') }
            default { $cell.transportFeature -eq "bridge-ramp-$code" -or $cell.transportFeature -eq "bridge-ramp-$($code.ToLowerInvariant())" }
        }
        $lift = if ($bridgeSide) { $bridgeHeight - $roadHeight } else { 0 }
        $expected = Get-ZMTransitionGateCoordinates $layout.bounds $code $lift
        Assert ($gateEntity.Get('origin') -eq ('{0} {1} {2}' -f $expected.x, $expected.y, (56 + $lift))) "$($cell.transportFeature) $code gate follows the actual selected deck."
        $landmark = @($entities | Where-Object { $_.Get('targetname') -eq "$($gateEntity.Get('zm_transition_direction').ToUpperInvariant())_ENTRANCE" })
        Assert ($landmark.Count -eq 1 -and $landmark[0].Get('origin') -eq ('{0} {1} {2}' -f $expected.arrivalX, $expected.arrivalY, $expected.arrivalZ)) 'Elevated exit and corresponding arrival share the same height contract.'
        $props = @($entities | Where-Object { $_.Get('targetname') -like "zm_transition_gate_$code`_barricade_*" })
        Assert ($props.Count -eq 4) 'Gate retains exactly four existing barricade props.'
        foreach ($prop in $props) {
            $z = [double](($prop.Get('origin') -split ' ')[2])
            Assert ($z -ge 42 + $lift -and $z -le 44 + $lift) 'Bridge barricades follow the road deck, not ground underneath it.'
        }
        $solid = $gateEntity.Child('solid')
        $zs = @($solid.Children | ForEach-Object {
            [regex]::Matches($_.Get('plane'), '\(([^)]+)\)') | ForEach-Object { [double](($_.Groups[1].Value -split ' ')[2]) }
        } | Sort-Object -Unique)
        Assert ($zs.Count -eq 2 -and $zs[0] -eq $lift -and $zs[1] -eq 112 + $lift) 'Actual trigger brush planes move with its origin and keep their original height.'
    }
    Assert (($layout.corePlacements | ConvertTo-Json -Depth 15) -ceq ($cell.tilePlacements | ConvertTo-Json -Depth 15)) 'Core assignments, IDs, yaw and frontage remain byte-equivalent in placement metadata.'
}
Assert ($storm.Count -eq 1) 'Exact Storm Drain 0,12 exists.'
$newLayout = Get-Content -Raw (Join-Path $coverageDirectory ([IO.Path]::ChangeExtension($storm[0].cellTemplateFilename, '.layout.json'))) | ConvertFrom-Json
Assert (@($newLayout.borderPlacements).Count -eq 24 - @($storm[0].suppressedBorderTiles).Count -and @($newLayout.borderPlacements | Group-Object { "$($_.tileX),$($_.tileY)" } | Where-Object Count -gt 1).Count -eq 0) 'Storm Drain retains every distinct border slot.'
Assert ((@($newLayout.waterSides) -join ',') -ceq 'W') 'Storm Drain coast attaches west at the original border.'
$stormWestOuter = @($newLayout.outerPlacements | Where-Object { $_.tileX -eq -2 })
Assert ($stormWestOuter.Count -eq 9 -and @($stormWestOuter | Where-Object { $_.template -notin $edgeSettings.oceanTemplates }).Count -eq 0) 'Storm Drain fills every west ocean outer slot with an authored ocean tile, including NW/SW corners.'
$stormShell = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw (Join-Path $coverageDirectory $storm[0].cellTemplateFilename)))
$stormFloor = @($stormShell.Child('world').Children | Where-Object { $_.Name -eq 'solid' -and ($_.Children | Where-Object Name -eq 'side' | Select-Object -First 1).Get('material') -eq 'HALFLIFE/BLACK' })
Assert ($stormFloor.Count -eq 1) 'Storm Drain retains one sealing floor.'
$floorX = @($stormFloor[0].Children | Where-Object Name -eq 'side' | ForEach-Object { $_.Child('vertices_plus').GetAll('v') } | ForEach-Object { [double]($_ -split '\s+')[0] } | Sort-Object -Unique)
Assert (($floorX -join ',') -eq '-2880,2880') 'Actual Storm Drain floor spans the revised west shoreline and preserves east clearance.'
$militaryMap = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'border_showcase_fixture_map.json') | ConvertFrom-Json
Disable-TestFixtureMotorways $militaryMap
$militaryCell = @($militaryMap.cells | Where-Object { $_.x -eq 5 -and $_.y -eq 2 })[0]
$militaryCell.environment.tags = @('military')
$militaryMapPath = Join-Path $OutputRoot 'military-map.json'
$militaryPlanPath = Join-Path $OutputRoot 'military-plan.json'
[IO.File]::WriteAllText($militaryMapPath, ($militaryMap | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData $militaryMapPath -CellDirectory $coverageDirectory -Output $militaryPlanPath -ListOutput (Join-Path $OutputRoot 'military-required.txt') | Out-Null
if (-not $?) { throw 'Military fixture planning failed.' }
$militaryPlan = Get-Content -Raw -LiteralPath $militaryPlanPath | ConvertFrom-Json
$militaryPlan.cells = @($militaryPlan.cells | Where-Object environmentProfile -eq 'military' | Select-Object -First 1)
Assert ($militaryPlan.cells.Count -eq 1) 'An actual military recipe must be exercised.'
[IO.File]::WriteAllText($militaryPlanPath, ($militaryPlan | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $militaryPlanPath -CellDirectory $coverageDirectory -SkyboxOutputDirectory (Join-Path $OutputRoot 'skybox') -RefreshGenerated -PruneStaleGenerated:$false | Out-Null
if (-not $?) { throw 'Military fixture generation failed.' }
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'coverage-required.txt'), [string[]]@((Get-ChildItem -LiteralPath $coverageDirectory -Filter '*.vmf').Name), [Text.UTF8Encoding]::new($false))
$compileMaps = @(
    'zz_preview_d4cbfaa03e4b-v1.vmf',
    'zz_preview_d4cbfaa03e4b-wtrnw-oceanw.vmf',
    'zz_preview_d4cbfaa03e4b-wtrnt.vmf',
    'zz_preview_a51608af6980-cp.vmf'
)
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'compile-required.txt'), [string[]]$compileMaps, [Text.UTF8Encoding]::new($false))
Write-Output "Outer edges: $script:passed assertions passed; isolated fixtures: $cellDirectory"
