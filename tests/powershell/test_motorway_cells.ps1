param([string]$OutputDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'skybox_models.psm1') -Force
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$root = $testsRepoRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'generated\phase_b_motorway_cells' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway cells: $Message" }
    $script:passed++
}
function Read-Entities {
    param([string]$Path)
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($Path))
    return @($tree.Children | Where-Object Name -eq entity)
}
$summaries = @(& (Join-Path $testsBinDirectory 'build_motorway_cell_preview.ps1') -OutputDirectory $OutputDirectory)
$planPath = Join-Path $OutputDirectory 'plan.json'
$settingsPath = Join-Path $OutputDirectory 'settings.json'
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
Assert ($plan.cells.Count -eq 2 -and $summaries.Count -eq 2 -and $plan.cellBounds.neighbourPitch -eq 5760) 'Two real expanded cells, unchanged authoritative pitch.'
foreach ($cell in $plan.cells) {
    $vertical = $cell.orientation -eq 'vertical'
    $yaw = if ($vertical) { 0 } else { 90 }
    $inspection = $cell.motorwayCellInspection
    Assert ($inspection.leases.Count -eq 27 -and $inspection.ringPlacements.Count -eq 4) 'Three-wide corridor reserves nine full core/border/outer stripes.'
    Assert ($inspection.yaw -eq $yaw -and $cell.tilePlacements.Count -eq 25) 'Actual planner preserves mapped yaw and all core occupancy records.'
    $keys = @($inspection.leases | ForEach-Object { "$($_.tileX),$($_.tileY)" })
    Assert (@($keys | Sort-Object -Unique).Count -eq 27) 'No duplicate core/ring reservations.'
    Assert (@($inspection.leases | Where-Object emitsInstance).Count -eq 9) 'Exactly one owner emits per stripe.'
    foreach ($ring in @('core', 'border', 'outer')) {
        Assert (@($inspection.leases | Where-Object ring -eq $ring).Count -eq $(if ($ring -eq 'core') { 15 } else { 6 })) 'Exact 15/6/6 leased-slot counts.'
    }
    $vmf = Join-Path $OutputDirectory ('src\' + $cell.cellTemplateFilename)
    $layout = Get-Content -Raw -LiteralPath ([IO.Path]::ChangeExtension($vmf, '.layout.json')) | ConvertFrom-Json
    Assert ($layout.vmfSha256 -eq (Get-FileHash -LiteralPath $vmf -Algorithm SHA256).Hash.ToLowerInvariant()) 'Layout fingerprint matches the actual newly generated cell VMF.'
    Assert ($layout.bounds.neighbourPitch -eq 5760 -and $layout.borderPlacements.Count -eq 20 -and $layout.outerPlacements.Count -eq 28) 'Builder emits complete rings with only explicitly leased slots replaced.'
    $entities = @(Read-Entities $vmf)
    $instances = @($entities | Where-Object { $_.Get('classname') -eq 'func_instance' })
    Assert ($instances.Count -eq 64) 'Full cell emits fifteen core, forty-eight ring and one skybox-room instance.'
    Assert (@($entities | Where-Object { $_.Get('zm_transition_gate') -eq '1' }).Count -eq 0) 'No legacy narrow transition trigger is misrepresented as wide travel.'
    $world = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf)).Child('world')
    Assert (@($world.Children | Where-Object Name -eq solid).Count -eq 10) 'Normal sealed cell shell and perimeter clips retained.'
    $roads = @($instances | Where-Object { $_.Get('file') -like '*motorway_3x1/tile_motorway.vmf' })
    Assert ($roads.Count -eq 9) 'Five core and four ring wide motorway instances actually written.'
    foreach ($instance in $instances) {
        $file = $instance.Get('file')
        $path = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $vmf) $file.Replace('/', '\')))
        Assert (Test-Path -LiteralPath $path -PathType Leaf) 'Every actual cell instance resolves to an existing current source.'
        Assert ($file -notmatch 'motorway_1x1|tile_motorway_[abc]\.vmf|tile_road_gate|buildings/|carparks/') 'No hidden legacy motorway, gate blocker or building fallback in inspection cell.'
        $p = [ZombieSim.Skybox.Vec3]::Parse($instance.Get('origin'))
        if ($file -like '*motorway_3x1/tile_motorway.vmf') {
            Assert ($instance.Get('angles') -eq "0 $yaw 0" -and $p.Z -eq 0) 'Actual cell-wide motorway yaw/Z remain authored.'
            Assert ($(if ($vertical) { $p.X -eq 0 } else { $p.Y -eq 0 })) 'Wide straight remains on the existing cell axis, not offset from guessed lanes.'
        } elseif ($instance.Get('targetname') -ne 'zm_skybox_room') {
            $cross = if ($vertical) { $p.X } else { $p.Y }
            $along = if ($vertical) { $p.Y } else { $p.X }
            Assert (-not ([Math]::Abs($cross) -lt 960 -and [Math]::Abs($along) -le 2560)) 'Scenery, border and outer instances do not duplicate occupied wide-corridor slots.'
        }
    }
    $positions = @($roads | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_.Get('origin')) } | Sort-Object $(if ($vertical) { 'Y' } else { 'X' }))
    for ($index = 1; $index -lt $positions.Count; $index++) {
        $distance = if ($vertical) { $positions[$index].Y - $positions[$index - 1].Y } else { $positions[$index].X - $positions[$index - 1].X }
        Assert ($distance -eq 640) 'Actual adjacent stripe instance origins are separated by one tile with no gap or overlap.'
    }
    Assert ($(if ($vertical) { $positions[0].Y -eq -2560 -and $positions[-1].Y -eq 2560 } else { $positions[0].X -eq -2560 -and $positions[-1].X -eq 2560 })) 'Both motorway ends reach the full outer footprint at +/-2880 through authored half-length320.'
    $shoulder = @($cell.tilePlacements | Where-Object { $_.role -in @('terrain', 'decoration') })
    Assert ($shoulder.Count -eq 10 -and @($shoulder | Where-Object role -eq terrain).Count -gt 0 -and @($shoulder | Where-Object role -eq decoration).Count -gt 0) 'Ten surrounding slots include real scenery and a terrain spawn, not a road-only showcase.'
    $cameraTree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf)).Child('cameras')
    Assert ($cameraTree.Get('activecamera') -eq '0' -and @($cameraTree.Children | Where-Object Name -eq camera).Count -eq 2) 'Cell opens with useful overview and road-height cameras.'
    foreach ($badType in @('ramp', 'corner', 'ocean', 'landmark')) {
        $bad = $cell | ConvertTo-Json -Depth 18 | ConvertFrom-Json
        $bad.PSObject.Properties.Remove('motorwayCellInspection')
        switch ($badType) {
            'ramp' { $bad.transportFeature = 'onramp-w' }
            'corner' { $bad.topology = 'motorway-corner' }
            'ocean' { $bad.skyboxOceanSides = @('W') }
            'landmark' { $bad.landmarks = @('Hospital') }
        }
        $rejected = $false
        try {
            Set-ZMStraightMotorwayCellInspection $bad $plan.chunkTemplateDirectory @{ straight = @{ vertical = 0; horizontal = 90 } }
        } catch {
            if ($_.Exception.Message -notlike '*unsupported cells never fall back*') { throw }
            $rejected = $true
        }
        Assert $rejected 'Unsupported cell combinations fail instead of fabricating a straight layout.'
    }
}
$hashes = @{}
foreach ($file in Get-ChildItem (Join-Path $OutputDirectory 'src') -File) { $hashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
& (Join-Path $testsBinDirectory 'build_motorway_cell_preview.ps1') -OutputDirectory $OutputDirectory | Out-Null
foreach ($file in Get-ChildItem (Join-Path $OutputDirectory 'src') -File) {
    Assert ($hashes.ContainsKey($file.Name) -and $hashes[$file.Name] -ceq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) 'Repeated real-cell generation retains identical VMF and layout bytes.'
}
$normalRoot = Join-Path $OutputDirectory 'normal-control'
[IO.Directory]::CreateDirectory($normalRoot) | Out-Null
$normalPlan = Join-Path $normalRoot 'plan.json'
& (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $settingsPath -MapData (Join-Path $OutputDirectory 'fixture-map.json') -Output $normalPlan -ListOutput (Join-Path $normalRoot 'required.txt') -CellDirectory (Join-Path $normalRoot 'src') | Out-Null
if (-not $?) { throw 'Normal cell control planner failed.' }
& (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $normalPlan -CellDirectory (Join-Path $normalRoot 'src') -SkyboxOutputDirectory (Join-Path $normalRoot 'skybox') -RefreshGenerated | Out-Null
if (-not $?) { throw 'Normal cell control builder failed.' }
$control = Get-Content -Raw -LiteralPath $normalPlan | ConvertFrom-Json
foreach ($cell in $control.cells) {
    Assert ($null -eq $cell.PSObject.Properties['motorwayCellInspection']) 'Ordinary planner remains unopted-in.'
    $vmf = Join-Path $normalRoot ('src\' + $cell.cellTemplateFilename)
    $instances = @(Read-Entities $vmf | Where-Object { $_.Get('classname') -eq 'func_instance' })
    Assert (@($instances | Where-Object { $_.Get('file') -like '*motorway_3x1*' }).Count -eq 0) 'Ordinary builder never silently switches families.'
    Assert (@($cell.tilePlacements | Where-Object { $_.role -like 'motorway_*' }).Count -eq 0) 'Normal core roles preserved.'
    foreach ($placement in $cell.tilePlacements | Where-Object { $null -eq $_.PSObject.Properties['emitsInstance'] -or $_.emitsInstance }) {
        $target = 'zm_tile_' + ([string]$placement.role).ToLowerInvariant() + "_$($placement.tileX)_$($placement.tileY)"
        $matching = @($instances | Where-Object { $_.Get('targetname') -eq $target })
        Assert ($matching.Count -eq 1) 'Original normal placement still emits exactly once.'
        $p = [ZombieSim.Skybox.Vec3]::Parse($matching[0].Get('origin'))
        $width = if ($null -eq $placement.PSObject.Properties['footprintWidth']) { 1 } else { $placement.footprintWidth }
        $height = if ($null -eq $placement.PSObject.Properties['footprintHeight']) { 1 } else { $placement.footprintHeight }
        Assert ($p.X -eq ($placement.tileX - 2 + ($width - 1) / 2.0) * 640 -and $p.Y -eq (2 - $placement.tileY - ($height - 1) / 2.0) * 640) 'Original normal core origin formula remains unchanged.'
    }
}
$rejected = $false
try {
    & (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1') -WorldProfile preview -SettingsPath $settingsPath -PlanData $planPath -CellDirectory (Join-Path $OutputDirectory 'src') -SkyboxOutputDirectory (Join-Path $OutputDirectory 'skybox') | Out-Null
} catch {
    if ($_.Exception.Message -notlike '*inspection requires explicit isolated*') { throw }
    $rejected = $true
}
Assert $rejected 'Inspection recipes cannot be consumed without explicit builder opt-in.'
& (Join-Path $testsBinDirectory 'check_required_cells.ps1') -WorldProfile preview -SettingsPath $settingsPath -RequiredCellList (Join-Path $OutputDirectory 'required.txt') -CellDirectory (Join-Path $OutputDirectory 'src')
if (-not $?) { throw 'Inspection required-cell check failed.' }
Write-Host "Motorway cells: $passed assertions passed; two complete generated cells and normal-generation controls verified. Compilation/solid clearance/live travel not claimed."
