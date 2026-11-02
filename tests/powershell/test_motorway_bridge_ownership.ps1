param(
    [Parameter(Mandatory = $true)][string]$PlanData,
    [string]$VmfDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Import-Module (Join-Path $root 'bin\motorway_grid_placements.psm1') -Force
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
if (-not [string]::IsNullOrWhiteSpace($VmfDirectory)) {
    Import-Module (Join-Path $root 'bin\skybox_models.psm1') -Force
}
$script:passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway bridge ownership: $Message" }
    $script:passed++
}

function Get-Signature {
    param([object]$Value)
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

$bridgeCells = @($plan.cells | Where-Object {
    $null -ne $_.PSObject.Properties['motorwayAssembly'] -and $null -ne $_.motorwayAssembly -and
    $_.motorwayAssembly.schemaVersion -eq 2 -and
    @($_.motorwayAssembly.assemblies | Where-Object {
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -eq 'tile_motorway_road_bridge.vmf'
    }).Count -gt 0
})
Assert ($bridgeCells.Count -gt 0) 'The plan contains trusted motorway bridge cells.'
Assert (@($bridgeCells | Where-Object { $_.x -eq 17 -and $_.y -eq 2 }).Count -eq 1) 'The reported grid (17,2) is covered.'
Assert (@($bridgeCells.transportFeature | Sort-Object -Unique).Count -eq 2) 'Both crossing orientations are covered.'

foreach ($cell in $bridgeCells) {
    $coordinate = "$($cell.x),$($cell.y)"
    $recipe = $cell | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    # Occupancy dimensions are added by the planner after the grid owner runs.
    foreach ($placement in @($recipe.tilePlacements | Where-Object role -eq 'motorway_external_occupied')) {
        foreach ($name in @('footprintWidth', 'footprintHeight', 'ownerTileX', 'ownerTileY')) {
            $placement.PSObject.Properties.Remove($name)
        }
    }
    $bridgeOwners = @($cell.motorwayAssembly.assemblies | Where-Object {
        [IO.Path]::GetFileName(([string]$_.template).Replace('/', '\')) -eq 'tile_motorway_road_bridge.vmf'
    } | ForEach-Object { [string]$_.owner })
    $bridgeSlots = @{}
    foreach ($lease in $cell.motorwayAssembly.leases) {
        if ($lease.ring -eq 'core' -and [string]$lease.owner -in $bridgeOwners) {
            $bridgeSlots["$($lease.tileX),$($lease.tileY)"] = [string]$lease.owner
        }
    }
    Assert ($bridgeSlots.Count -gt 0) "Bridge ownership exists at $coordinate."
    $outsideBefore = @($recipe.tilePlacements | Where-Object { -not $bridgeSlots.ContainsKey("$($_.tileX),$($_.tileY)") })
    $outsideRoads = @($outsideBefore | Where-Object { $_.template -eq 'roads/tile_road_bridge.vmf' })
    Assert ($outsideRoads.Count -eq 2) "Both ordinary bridge approaches outside the motorway footprint remain at $coordinate."

    $yaw = if ($cell.transportFeature -eq 'bridge-horizontal') { 90 } else { 0 }
    $recipe.tilePlacements = @(foreach ($placement in $recipe.tilePlacements) {
        if ($bridgeSlots.ContainsKey("$($placement.tileX),$($placement.tileY)")) {
            [pscustomobject]@{
                tileX = $placement.tileX; tileY = $placement.tileY
                template = 'roads/tile_road_bridge.vmf'; rotationYaw = $yaw; role = 'bridge_road'
            }
        } else { $placement }
    })
    $contract = Set-ZMTrustedMotorwayGridContract $recipe $cell.motorwayAssembly $plan.cellTileGridSize `
        $plan.cellBounds.tileSize 2 'roads/tile_road.vmf' 'roads/tile_road_bridge.vmf' `
        ([ordered]@{ N = 0; E = 90; S = 0; W = 90 })

    foreach ($placement in $recipe.tilePlacements) {
        $key = "$($placement.tileX),$($placement.tileY)"
        if ($bridgeSlots.ContainsKey($key)) {
            Assert ($placement.role -eq 'motorway_external_occupied' -and -not $placement.emitsInstance -and
                $placement.placementId -ceq $bridgeSlots[$key]) "The motorway bridge alone emits geometry in slot $key at $coordinate."
        }
    }
    $outsideAfter = @($recipe.tilePlacements | Where-Object { -not $bridgeSlots.ContainsKey("$($_.tileX),$($_.tileY)") })
    Assert ((Get-Signature $outsideBefore) -ceq (Get-Signature $outsideAfter)) "Every placement outside the bridge footprint is unchanged at $coordinate."
    Assert ((Get-Signature $contract) -ceq (Get-Signature $cell.motorwayAssembly)) "Motorway geometry, continuations, gates and leases are unchanged at $coordinate."

    if (-not [string]::IsNullOrWhiteSpace($VmfDirectory)) {
        $vmfPath = Join-Path $VmfDirectory $cell.cellTemplateFilename
        $layoutPath = [IO.Path]::ChangeExtension($vmfPath, '.layout.json')
        $layout = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
        Assert ($layout.vmfSha256 -ceq (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()) "The layout matches the exact generated VMF at $coordinate."
        Assert ((Get-Signature $layout.corePlacements) -ceq (Get-Signature $cell.tilePlacements)) "Generated core placements match the current plan at $coordinate."
        $vmf = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmfPath))
        $instances = @($vmf.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' })
        $ordinaryBridges = @($instances | Where-Object {
            [IO.Path]::GetFileName(([string]$_.Get('file')).Replace('/', '\')) -eq 'tile_road_bridge.vmf'
        })
        Assert ($ordinaryBridges.Count -eq 6) "Only two core approaches and four border/outer ordinary bridges are emitted at $coordinate."
        foreach ($instance in $ordinaryBridges) {
            $position = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
            $tileX = [int][Math]::Round($position.X / $plan.cellBounds.tileSize) + 2
            $tileY = 2 - [int][Math]::Round($position.Y / $plan.cellBounds.tileSize)
            Assert (-not $bridgeSlots.ContainsKey("$tileX,$tileY")) "No ordinary bridge instance overlaps the motorway bridge in the generated VMF at $coordinate."
        }
    }
}

Write-Output "Motorway bridge ownership: $script:passed assertions passed across $($bridgeCells.Count) cells."
