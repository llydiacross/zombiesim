Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $projectRoot 'bin\claim_tiles.psm1') -Force

$script:Failures = 0
$script:Passes = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:Passes++ } else { $script:Failures++; Write-Host "FAIL: $Message" -ForegroundColor Red }
}

function New-Placement {
    param([int]$X, [int]$Y, [string]$Role, [string]$Template, [int]$W = 1, [int]$H = 1, [bool]$Emits = $true, [int]$OwnerX = -1, [int]$OwnerY = -1)
    if ($OwnerX -lt 0) { $OwnerX = $X }
    if ($OwnerY -lt 0) { $OwnerY = $Y }
    [pscustomobject]@{ tileX = $X; tileY = $Y; role = $Role; template = $Template; footprintWidth = $W; footprintHeight = $H; emitsInstance = $Emits; ownerTileX = $OwnerX; ownerTileY = $OwnerY }
}

function Get-Keys { param([object[]]$Tiles) @($Tiles | ForEach-Object { "$($_[0]),$($_[1])" }) }

$layout = [pscustomobject]@{
    bounds = [pscustomobject]@{ coreTileGridSize = 5 }
    corePlacements = @(
        (New-Placement 0 0 'terrain' 'terrain/tile_grass_1a.vmf'),
        (New-Placement 4 4 'decoration' 'decorations\tile_trees_1a.vmf'),
        (New-Placement 4 0 'decoration' 'terrain/tile_dirt_1a.vmf'),
        (New-Placement 2 2 'road_center' 'roads/tile_road_crossroads.vmf'),
        (New-Placement 1 0 'building' 'buildings/tile_building_1a.vmf'),
        (New-Placement 0 4 'motorway_external_occupied' 'terrain/tile_grass_1a.vmf'),
        (New-Placement 1 4 'terrain' 'terrain/tile_grass_2x.vmf' 2 1),
        (New-Placement 3 0 'terrain' 'terrain/tile_grass_1a.vmf' 1 1 $false),
        (New-Placement 3 4 'terrain' 'terrain/tile_grass_1a.vmf' 1 1 $true 2 4),
        (New-Placement 0 2 'terrain' 'buildings/tile_building_1a.vmf'),
        (New-Placement 4 2 'terrain' 'terrain/tile_grass_1a.vmf'),
        (New-Placement 4 2 'decoration' 'decorations/tile_bushes_1a.vmf')
    )
}

$keys = Get-Keys (Get-ZMClaimTiles $layout)
Assert-True ($keys -contains '-2,2') 'NW terrain (0,0) -> (-2,2)'
Assert-True ($keys -contains '2,-2') 'SE decoration (4,4) -> (2,-2)'
Assert-True ($keys -contains '2,2') 'decoration role with terrain template is claimable'
Assert-True ($keys.Count -eq 3) "exactly three claimable tiles; got $($keys -join ' ')"
Assert-True ($keys -notcontains '0,0') 'road centre excluded'
Assert-True ($keys -notcontains '-1,2') 'building excluded'
Assert-True ($keys -notcontains '-2,-2') 'motorway_external_occupied excluded'
Assert-True ($keys -notcontains '-1,-2') 'multi-tile footprint excluded'
Assert-True ($keys -notcontains '1,2') 'non-emitting placement excluded'
Assert-True ($keys -notcontains '1,-2') 'placement owned by another tile excluded'
Assert-True ($keys -notcontains '-2,0') 'non-terrain template excluded'
Assert-True ($keys -notcontains '2,0') 'stacked placements excluded'

$empty = Get-ZMClaimTiles ([pscustomobject]@{ bounds = [pscustomobject]@{ coreTileGridSize = 5 }; corePlacements = @() })
Assert-True (@($empty).Count -eq 0) 'layout without placements yields no claim tiles'

$threw = $false
try { Get-ZMClaimTiles ([pscustomobject]@{ bounds = [pscustomobject]@{ coreTileGridSize = 4 }; corePlacements = @() }) | Out-Null } catch { $threw = $true }
Assert-True $threw 'even grid size rejected'
$threw = $false
try { Get-ZMClaimTiles ([pscustomobject]@{ bounds = [pscustomobject]@{ coreTileGridSize = 5 }; corePlacements = @((New-Placement 5 0 'terrain' 'terrain/a.vmf')) }) | Out-Null } catch { $threw = $true }
Assert-True $threw 'out-of-grid placement rejected'

Write-Host "Claim tiles: $script:Passes passed, $script:Failures failed."
if ($script:Failures -gt 0) { exit 1 }
