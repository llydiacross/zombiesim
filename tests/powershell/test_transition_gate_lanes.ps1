Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'transition_gates.psm1') -Force

$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Transition gate lane checks: $Message" }
    $script:passed++
}

$directions = @{
    N = @{ x = 0; y = 2208; forward = @(0, 1); right = @(1, 0); laterals = @(-512, 528) }
    E = @{ x = 2208; y = 0; forward = @(1, 0); right = @(0, -1); laterals = @(-528, 512) }
    S = @{ x = 0; y = -2208; forward = @(0, -1); right = @(-1, 0); laterals = @(-528, 512) }
    W = @{ x = -2208; y = 0; forward = @(-1, 0); right = @(0, 1); laterals = @(-512, 528) }
}

foreach ($direction in $directions.Keys) {
    $contract = $directions[$direction]
    $lanes = @(
        [pscustomobject]@{
            lateral = $contract.laterals[0]; width = 416; deckZ = 68
            arrowX = 0; arrowY = 0; arrivalX = 0; arrivalY = 0
        },
        [pscustomobject]@{
            lateral = $contract.laterals[1]; width = 416; deckZ = 68
            arrowX = 0; arrowY = 0; arrivalX = 0; arrivalY = 0
        }
    )
    $gate = [pscustomobject]@{
        direction = $direction
        directionName = @{ N = 'north'; E = 'east'; S = 'south'; W = 'west' }[$direction]
        route = 'motorway'
        x = $contract.x; y = $contract.y; zOffset = 32
        lanes = $lanes; lateralMin = -736; lateralMax = 736
        arrivalX = 0; arrivalY = 1824; arrivalZ = 72
    }
    $triggers = @(Expand-ZMTransitionGateLanes @($gate))
    Assert ($triggers.Count -eq 2) "$direction emits one trigger for each carriageway."
    for ($index = 0; $index -lt 2; $index++) {
        $trigger = $triggers[$index]
        $lane = $lanes[$index]
        Assert ($trigger.laneIndex -eq ($index + 1)) "$direction preserves the carriageway index."
        Assert ($trigger.lateralMin -eq ($lane.lateral - 208) -and
            $trigger.lateralMax -eq ($lane.lateral + 208)) "$direction trigger spans exactly one 416-unit carriageway."
        $bounds = Get-ZMTransitionTriggerBounds $trigger
        $acrossWidth = [Math]::Abs($contract.right[0]) * ($bounds.maxX - $bounds.minX) +
            [Math]::Abs($contract.right[1]) * ($bounds.maxY - $bounds.minY)
        $crossCentre = (($bounds.minX + $bounds.maxX) / 2 - $gate.x) * $contract.right[0] +
            (($bounds.minY + $bounds.maxY) / 2 - $gate.y) * $contract.right[1]
        $alongCentre = (($bounds.minX + $bounds.maxX) / 2 - $gate.x) * $contract.forward[0] +
            (($bounds.minY + $bounds.maxY) / 2 - $gate.y) * $contract.forward[1]
        Assert ($acrossWidth -eq 416 -and $crossCentre -eq $lane.lateral -and $alongCentre -eq 0) "$direction trigger is centred on its planned lane."
        Assert ($bounds.minZ -eq 32 -and $bounds.maxZ -eq 144) "$direction keeps the approved trigger deck height and vertical extent."
        Assert ($trigger.arrivalX -eq 0 -and $trigger.arrivalY -eq 1824) "$direction keeps the existing 384-unit inward arrival."
        $props = @(Get-ZMTransitionBarricadeProps $trigger)
        Assert ($props.Count -eq 2 -and
            [Math]::Abs((($props[0].across + $props[1].across) / 2) - $lane.lateral) -lt 1) "$direction barricades remain on the selected carriageway."
    }
}

$roadGate = [pscustomobject]@{
    direction = 'E'; directionName = 'east'; route = 'road'
    x = 2208; y = 640; zOffset = 160
    lanes = @([pscustomobject]@{
        lateral = 0; width = 256; deckZ = 196
        arrowX = 2112; arrowY = 640; arrivalX = 2080; arrivalY = 640
    })
    lateralMin = -128; lateralMax = 128
    arrivalX = 2080; arrivalY = 640; arrivalZ = 200
}
$roadTriggers = @(Expand-ZMTransitionGateLanes @($roadGate))
Assert ($roadTriggers.Count -eq 1 -and $null -eq $roadTriggers[0].PSObject.Properties['laneIndex']) 'Ordinary roads keep one combined trigger.'
$roadBounds = Get-ZMTransitionTriggerBounds $roadTriggers[0]
Assert (($roadBounds.maxX - $roadBounds.minX) -eq 64 -and
    ($roadBounds.maxY - $roadBounds.minY) -eq 256) 'Ordinary-road trigger dimensions remain unchanged.'
Assert (@(Get-ZMTransitionBarricadeProps $roadTriggers[0]).Count -eq 4) 'Ordinary-road barricades remain unchanged.'

$legacyGate = [pscustomobject]@{
    direction = 'N'; directionName = 'north'; x = 0; y = 2208; yaw = 90
    zOffset = 0; arrivalX = 0; arrivalY = 2080; arrivalZ = 40
}
$legacyTriggers = @(Expand-ZMTransitionGateLanes @($legacyGate))
Assert ($legacyTriggers.Count -eq 1 -and $null -eq $legacyTriggers[0].PSObject.Properties['laneIndex']) 'Legacy lane-less gates remain unchanged.'

$arrivalTemplate = 'entity { "classname" "info_landmark" "targetname" "NORTH_ENTRANCE" "origin" "0 0 0" }'
$arrivalGates = @(
    [pscustomobject]@{ directionName = 'north'; arrivalX = -512; arrivalY = 1824; arrivalZ = 72 },
    [pscustomobject]@{ directionName = 'north'; arrivalX = -512; arrivalY = 1824; arrivalZ = 72 }
)
$arrivalVmf = Set-ZMTransitionArrivalLandmarks $arrivalTemplate $arrivalGates
Assert ([regex]::Matches($arrivalVmf, '"origin" "-512 1824 72"').Count -eq 1) 'Shared carriageway triggers write the arrival landmark once.'

Write-Output "Transition gate lane checks: $passed assertions passed."
