param([string]$OutputDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root ('generated\motorway_onramp_road_shift_' + [guid]::NewGuid().ToString('N'))
}
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway on-ramp road shift: $Message" }
    $script:passed++
}
function Get-Instance {
    param([object[]]$Instances, [string]$Owner)
    $matches = @($Instances | Where-Object { $_.Get('targetname') -eq "zm_assembly_$Owner" })
    if ($matches.Count -ne 1) { throw "Expected one emitted instance for '$Owner'; found $($matches.Count)." }
    return $matches[0]
}
try {
    & (Join-Path $PSScriptRoot 'build_motorway_cell_preview.ps1') -NormalComplex -SkipInfill -OutputDirectory $OutputDirectory | Out-Null
    if (-not $?) { throw 'Normal complex on-ramp fixtures failed to generate.' }
    $plan = Get-Content -Raw (Join-Path $OutputDirectory 'plan.json') | ConvertFrom-Json
    $straightCells = @($plan.cells | Where-Object {
        $_.x -eq 17 -and $_.y -eq 10 -and $_.topology -eq 'motorway-straight' -and $_.transportFeature -eq 'onramp-e'
    })
    $deadendCells = @($plan.cells | Where-Object {
        $_.x -eq 6 -and $_.y -eq 23 -and $_.topology -eq 'motorway-deadend' -and $_.transportFeature -eq 'onramp-e'
    })
    Assert ($straightCells.Count -eq 1 -and $deadendCells.Count -eq 1) 'Both intended east on-ramp cells are present in the current seed-1337 plan.'

    foreach ($cell in @($straightCells + $deadendCells)) {
        $contract = $cell.motorwayAssembly
        $shift = @($contract.ordinaryRoadPlacementShifts | Where-Object {
            $_.heading -eq 'E' -and $_.axis -eq 'y' -and $_.units -eq 640 -and $_.scope -eq 'ordinary_onramp_road_and_following_tiles_only'
        })
        Assert ($shift.Count -eq 1) 'The east ordinary-road branch records one northward grid shift.'
        $vmf = Join-Path (Join-Path $OutputDirectory 'src') $cell.cellTemplateFilename
        $layout = Get-Content -Raw ([IO.Path]::ChangeExtension($vmf, '.layout.json')) | ConvertFrom-Json
        Assert ($layout.vmfSha256 -ceq (Get-FileHash -LiteralPath $vmf -Algorithm SHA256).Hash.ToLowerInvariant()) 'The instance fixture matches the current layout fingerprint.'
        $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf))
        $instances = @($tree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' })

        if ($cell.topology -eq 'motorway-straight') {
            $motorwayRamp = @($contract.assemblies | Where-Object {
                [IO.Path]::GetFileName($_.template) -eq 'tile_motorway_onramp_3x4.vmf' -and $_.owner -like '*/main'
            })
            Assert ($motorwayRamp.Count -eq 1 -and $motorwayRamp[0].origin.x -eq -320 -and
                $motorwayRamp[0].origin.y -eq 0 -and $motorwayRamp[0].yaw -eq 270) 'The motorway on-ramp piece stays at its authored generated position.'
            $northSouth = @($contract.assemblies | Where-Object {
                [IO.Path]::GetFileName($_.template) -eq 'tile_motorway.vmf' -and $_.owner -match '/(N|S)/(continuation|stripe[0-9]+)$'
            })
            Assert (@($northSouth | Where-Object { $_.origin.x -ne 0 }).Count -eq 0) 'The north/south motorway continuation stays on its original centreline.'
            Assert (@($northSouth | Where-Object { $_.origin.y -notin @(-2560, -1920, -1280, 1280, 1920, 2560) }).Count -eq 0) 'The north/south motorway slots remain unchanged.'
            $roadApproach = @($contract.assemblies | Where-Object {
                [IO.Path]::GetFileName($_.template) -eq 'tile_road_onramp.vmf' -and $_.owner -like '*/E/road_approach'
            })
            $roadFollowing = @($contract.assemblies | Where-Object {
                [IO.Path]::GetFileName($_.template) -eq 'tile_road.vmf' -and $_.owner -match '/E/road[0-9]+$'
            })
            Assert ($roadApproach.Count -eq 1 -and $roadApproach[0].origin.x -eq 1280 -and $roadApproach[0].origin.y -eq 128) 'Only the ordinary on-ramp road tile moves north by one640 slot.'
            Assert ($roadFollowing.Count -eq 2 -and @($roadFollowing | Where-Object { $_.origin.y -ne 128 }).Count -eq 0) 'Both following ordinary-road tiles move with the on-ramp road tile.'
            $gate = @(Get-ZMComplexMotorwayGates $contract $plan.chunkTemplateDirectory | Where-Object { $_.direction -eq 'E' -and $_.route -eq 'road' })
            Assert ($gate.Count -eq 1 -and $gate[0].x -eq 2208 -and $gate[0].y -eq 128) 'East road gate follows the shifted road lane rather than the motorway center.'
            $mainInstance = Get-Instance $instances $motorwayRamp[0].owner
            $mainPosition = [ZombieSim.Skybox.Vec3]::Parse($mainInstance.Get('origin'))
            Assert ($mainPosition.X -eq -320 -and $mainPosition.Y -eq 0 -and $mainPosition.Z -eq 0) 'The emitted motorway piece itself is not translated.'
        } else {
            $approaches = @($contract.ordinaryRoadApproaches | Where-Object heading -eq 'E')
            Assert ($approaches.Count -eq 1 -and $approaches[0].boundaryPort.position.y -eq 640 -and $approaches[0].entryAxis -eq -640) 'The previously reviewed deadend road dogleg moves north as requested.'
            $roadApproach = @($contract.assemblies | Where-Object {
                [IO.Path]::GetFileName($_.template) -eq 'tile_road_onramp.vmf' -and $_.owner -like '*/E/road_approach'
            })
            Assert ($roadApproach.Count -eq 1 -and $roadApproach[0].origin.y -eq 2048) 'The deadend on-ramp road tile moves north with its dogleg.'
            $gate = @(Get-ZMComplexMotorwayGates $contract $plan.chunkTemplateDirectory | Where-Object { $_.direction -eq 'E' -and $_.route -eq 'road' })
            Assert ($gate.Count -eq 1 -and $gate[0].y -eq 640) 'The deadend east road gate follows its shifted boundary mouth.'
        }

        foreach ($assembly in $contract.assemblies | Where-Object { $_.owner -match '/E/' -and ($_.template -match 'tile_road_onramp|tile_road\\.vmf|tile_road_corner|tile_road_straight_768') }) {
            $entity = Get-Instance $instances $assembly.owner
            $actual = [ZombieSim.Skybox.Vec3]::Parse($entity.Get('origin'))
            Assert ($actual.X -eq $assembly.origin.x -and $actual.Y -eq $assembly.origin.y -and $actual.Z -eq $assembly.origin.z) 'The north-shifted ordinary-road instance is serialized at its planned origin.'
        }
    }
}
finally {
    if (Test-Path -LiteralPath $OutputDirectory -PathType Container) {
        Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
    }
}
Write-Output "Motorway on-ramp road shift: $passed assertions passed; east road-only offset tested for straight and deadend cells."
