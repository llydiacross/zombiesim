param(
    [Parameter(Mandatory = $true)][string]$PlanData,
    [Parameter(Mandatory = $true)][string]$RuntimeData,
    [string]$OutputPlan = '',
    [string]$RequiredCellList = '',
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $projectRoot $Path))
}

function Get-GateSignature {
    param([object]$Gate)

    $route = if ($null -ne $Gate.PSObject.Properties['route']) { [string]$Gate.route } else { 'motorway' }
    return ([ordered]@{
        direction = [string]$Gate.direction
        route = $route
        x = [double]$Gate.x
        y = [double]$Gate.y
        lateralMin = [double]$Gate.lateralMin
        lateralMax = [double]$Gate.lateralMax
        deckZ = [double]$Gate.deckZ
        arrivalLane = [int]$Gate.arrivalLane
        lanes = @($Gate.lanes | ForEach-Object {
            [ordered]@{
                lateral = [double]$_.lateral
                width = [double]$_.width
                deckZ = [double]$_.deckZ
                arrowX = [double]$_.arrowX
                arrowY = [double]$_.arrowY
                arrivalX = [double]$_.arrivalX
                arrivalY = [double]$_.arrivalY
                sourcePort = [string]$_.sourcePort
            }
        })
    } | ConvertTo-Json -Depth 20 -Compress)
}

function Get-PlacementSnapshot {
    param([object]$Plan)

    $snapshot = @($Plan.cells | Sort-Object x, y | ForEach-Object {
        $assembly = $null
        if ($null -ne $_.PSObject.Properties['motorwayAssembly']) {
            $contract = $_.motorwayAssembly
            $getOptional = {
                param([object]$Object, [string]$Name)
                $property = $Object.PSObject.Properties[$Name]
                if ($null -eq $property) { return $null }
                return $property.Value
            }
            $assembly = [ordered]@{
                schemaVersion = $contract.schemaVersion
                assemblies = & $getOptional $contract 'assemblies'
                leases = & $getOptional $contract 'leases'
                connections = & $getOptional $contract 'connections'
                gridSnap = & $getOptional $contract 'gridSnap'
                ordinaryRoadPlacementShifts = & $getOptional $contract 'ordinaryRoadPlacementShifts'
            }
        }
        [ordered]@{
            x = $_.x
            y = $_.y
            tilePlacements = $_.tilePlacements
            assembly = $assembly
        }
    })
    return $snapshot | ConvertTo-Json -Depth 60 -Compress
}

$planPath = Resolve-ProjectPath $PlanData
$runtimePath = Resolve-ProjectPath $RuntimeData
$outputPath = if ([string]::IsNullOrWhiteSpace($OutputPlan)) { $planPath } else { Resolve-ProjectPath $OutputPlan }
$listPath = if ([string]::IsNullOrWhiteSpace($RequiredCellList)) {
    $loadedPlan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    Resolve-ProjectPath ([string]$loadedPlan.requiredCellList)
} else {
    Resolve-ProjectPath $RequiredCellList
}

if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Approved plan not found: $planPath" }
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "Prior runtime export not found: $runtimePath" }
if ([string]::Equals($outputPath, $runtimePath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The plan output must not overwrite the runtime export.'
}

$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
if ($plan.mapSeed -ne $runtime.world.seed -or @($runtime.world.grid).Count -ne 2 -or
    @($runtime.world.grid | Where-Object { $_ -ne $plan.mapGridCells }).Count -gt 0) {
    throw 'The approved plan and prior runtime export do not describe the same world seed and grid.'
}
if (@($plan.cells).Count -ne @($runtime.cells).Count) {
    throw 'The approved plan and prior runtime export contain different cell counts.'
}

$placementSnapshot = Get-PlacementSnapshot $plan
$runtimeByMap = @{}
foreach ($runtimeCell in $runtime.cells) {
    $mapName = [string]$runtimeCell.map
    if ([string]::IsNullOrWhiteSpace($mapName) -or [IO.Path]::GetFileName($mapName) -ne $mapName) {
        throw 'Prior runtime export contains an invalid cell map name.'
    }
    $key = $mapName.ToLowerInvariant()
    if (-not $runtimeByMap.ContainsKey($key)) {
        $runtimeByMap[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $runtimeByMap[$key].Add($runtimeCell)
}

$planCellsByCoordinate = @{}
foreach ($cell in $plan.cells) {
    $coordinate = "$($cell.x),$($cell.y)"
    if ($planCellsByCoordinate.ContainsKey($coordinate)) { throw "Approved plan repeats logical cell $coordinate." }
    $planCellsByCoordinate[$coordinate] = $cell
}
$staleOrdinaryMapNameRecords = 0
foreach ($runtimeCell in $runtime.cells) {
    $cellId = [int]$runtimeCell.id
    if ($cellId -lt 0 -or $cellId -ge $plan.cells.Count) { throw "Prior runtime cell ID is outside the approved grid: $cellId" }
    $x = $cellId % [int]$plan.mapGridCells
    $y = [int][Math]::Floor($cellId / [double]$plan.mapGridCells)
    $plannedCell = $planCellsByCoordinate["$x,$y"]
    if ($null -eq $plannedCell) { throw "Prior runtime cell has no approved logical coordinate: $cellId" }
    if ($runtimeCell.topology -cne $plannedCell.topology -or
        (@($runtimeCell.entrances | Sort-Object -Unique) -join ',') -cne
        (@($plannedCell.activeEntrances | Sort-Object -Unique) -join ',')) {
        throw "Prior runtime topology or gate directions differ at logical cell $x,$y."
    }
    $expectedMapName = [IO.Path]::GetFileNameWithoutExtension([string]$plannedCell.cellTemplateFilename)
    if ([string]$runtimeCell.map -ine $expectedMapName) {
        $hasMotorwayContract = $null -ne $plannedCell.PSObject.Properties['motorwayAssembly']
        $hasRuntimeGates = $null -ne $runtimeCell.PSObject.Properties['motorwayGates'] -and
            @($runtimeCell.motorwayGates).Count -gt 0
        if ($hasMotorwayContract -or $hasRuntimeGates) {
            throw "Prior runtime map differs for a motorway-gated cell at logical cell $x,$y."
        }
        $staleOrdinaryMapNameRecords++
    }
}

$oldToNewName = @{}
$newNames = @{}
$assemblyCount = 0
$schemaOneCount = 0
$schemaTwoCount = 0
$gateRecordCount = 0
$oldOceanCellCount = @($plan.cells | Where-Object { $_.cellTemplateFilename -match '-oceanw-edge2\.vmf$' }).Count
foreach ($cell in $plan.cells) {
    $oldFilename = [string]$cell.cellTemplateFilename
    if ($oldFilename -notmatch '-edge2\.vmf$') {
        throw "Approved recipe does not have the retired edge2 suffix: $oldFilename"
    }
    $newFilename = [regex]::Replace($oldFilename, '-edge2\.vmf$', '.vmf')
    $newKey = $newFilename.ToLowerInvariant()
    if ($newNames.ContainsKey($newKey) -and $newNames[$newKey] -ne $oldFilename.ToLowerInvariant()) {
        throw "Recipe rename creates a collision: $newFilename"
    }
    $newNames[$newKey] = $oldFilename.ToLowerInvariant()
    $oldMapName = [IO.Path]::GetFileNameWithoutExtension($oldFilename)
    $oldToNewName[$oldFilename.ToLowerInvariant()] = $newFilename

    if ($null -ne $cell.PSObject.Properties['motorwayAssembly']) {
        $contract = $cell.motorwayAssembly
        if ($null -ne $cell.PSObject.Properties['motorwayCellInspection']) {
            throw "Approved normal plan unexpectedly contains an inspection-only motorway contract: $oldFilename"
        }
        $runtimeKey = $oldMapName.ToLowerInvariant()
        if (-not $runtimeByMap.ContainsKey($runtimeKey)) {
            throw "Prior runtime export has no gate record for approved motorway recipe $oldFilename"
        }
        $matchingCells = @($runtimeByMap[$runtimeKey])
        $withGates = @($matchingCells | Where-Object {
            $null -ne $_.PSObject.Properties['motorwayGates']
        })
        if ($withGates.Count -ne $matchingCells.Count -or $withGates.Count -eq 0) {
            throw "Prior runtime gate records are incomplete for approved motorway recipe $oldFilename"
        }
        $gateSignatures = @($withGates | ForEach-Object {
            (@($_.motorwayGates | ForEach-Object { Get-GateSignature $_ }) -join "`n")
        } | Sort-Object -Unique)
        if ($gateSignatures.Count -ne 1) {
            throw "Prior runtime gate records disagree for shared recipe $oldFilename"
        }

        $priorGates = @($withGates[0].motorwayGates)
        $gateDirections = @($priorGates.direction | Sort-Object -Unique)
        $activeDirections = @($cell.activeEntrances | Sort-Object -Unique)
        if (($gateDirections -join ',') -ne ($activeDirections -join ',')) {
            throw "Prior runtime gate directions disagree with the approved plan for $oldFilename"
        }
        if ($contract.schemaVersion -eq 1) {
            $planGateSignatures = @($contract.gates | ForEach-Object { Get-GateSignature $_ })
            $runtimeGateSignatures = @($priorGates | ForEach-Object { Get-GateSignature $_ })
            if (($planGateSignatures -join "`n") -cne ($runtimeGateSignatures -join "`n")) {
                throw "Prior runtime gate records differ from the approved straight contract for $oldFilename"
            }
            $schemaOneCount++
        } elseif ($contract.schemaVersion -eq 2) {
            $schemaTwoCount++
        } else {
            throw "Unsupported approved motorway contract version in $oldFilename"
        }

        $trustedGates = @($priorGates | ForEach-Object {
            $gate = $_.PSObject.Copy()
            $gate.status = 'trusted_prior_grid_gate_not_compiled_or_live'
            $gate
        })
        $contract | Add-Member -NotePropertyName assemblyAuthority -NotePropertyValue 'trusted_prior_approved_grid_layout' -Force
        $contract.PSObject.Properties.Remove('sourceSha256')
        $contract.PSObject.Properties.Remove('sourceFingerprints')
        $contract.PSObject.Properties.Remove('insertionSeam')
        $contract | Add-Member -NotePropertyName gates -NotePropertyValue $trustedGates -Force
        $gateRecordCount += $trustedGates.Count
        $assemblyCount++
    }

    $cell.cellTemplateFilename = $newFilename
    $cell.cellTemplateExists = $false
    if ($null -ne $cell.PSObject.Properties['cellTemplatePath']) {
        $cell.cellTemplatePath = Join-Path (Split-Path -Parent ([string]$cell.cellTemplatePath)) $newFilename
    }
}

if ($plan.requiredCellFiles.Count -ne $newNames.Count) {
    throw "Required recipe count $($plan.requiredCellFiles.Count) does not match the renamed plan recipe count $($newNames.Count)."
}
$newOceanCellCount = @($plan.cells | Where-Object { $_.cellTemplateFilename -match '-oceanw\.vmf$' }).Count
if ($oldOceanCellCount -eq 0 -or $newOceanCellCount -ne $oldOceanCellCount) {
    throw 'The filename migration must preserve every west-ocean recipe suffix.'
}
foreach ($required in $plan.requiredCellFiles) {
    $oldFilename = [string]$required.filename
    if (-not $oldToNewName.ContainsKey($oldFilename.ToLowerInvariant())) {
        throw "Required recipe is absent from the approved cell plan: $oldFilename"
    }
    $required.filename = $oldToNewName[$oldFilename.ToLowerInvariant()]
    $required.cellTemplateExists = $false
}
$plan.requiredCellFiles = @($plan.requiredCellFiles | Sort-Object filename)
$plan.missingCellFiles = @($plan.requiredCellFiles)
$plan.missingCellCount = $plan.requiredCellFiles.Count
$plan | Add-Member -NotePropertyName motorwayAssemblyReuse -NotePropertyValue ([pscustomobject]@{
    mode = 'trusted_prior_approved_grid_layout'
    geometryCompared = $false
    assemblyContracts = $assemblyCount
    schema1Contracts = $schemaOneCount
    schema2Contracts = $schemaTwoCount
    priorGateRecords = $gateRecordCount
    staleOrdinaryMapNameRecords = $staleOrdinaryMapNameRecords
}) -Force

foreach ($required in $plan.requiredCellFiles) {
    if ($required.filename -match '-edge2\.vmf$') { throw 'A retired edge2 recipe name remains after migration.' }
}
if ((Get-PlacementSnapshot $plan) -cne $placementSnapshot) {
    throw 'The filename/gate migration changed a saved tile placement, assembly origin, yaw or grid shift.'
}

$serializedPlan = $plan | ConvertTo-Json -Depth 100
if ($serializedPlan -match '-edge2') { throw 'A retired edge2 name remains in the migrated plan.' }
if (-not $ValidateOnly) {
    $directory = Split-Path -Parent $outputPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($outputPath, $serializedPlan + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $listDirectory = Split-Path -Parent $listPath
    if (-not (Test-Path -LiteralPath $listDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $listDirectory -Force | Out-Null
    }
    $names = @($plan.requiredCellFiles | ForEach-Object { [string]$_.filename })
    [IO.File]::WriteAllLines($listPath, $names, [Text.UTF8Encoding]::new($false))
}

Write-Output "Approved preview plan migration: $($plan.cells.Count) unchanged cell placements, $($plan.requiredCellFiles.Count) renamed recipes, $assemblyCount trusted motorway contracts ($schemaOneCount straight, $schemaTwoCount complex), $gateRecordCount reused gate records."
if ($staleOrdinaryMapNameRecords -gt 0) {
    Write-Output "$staleOrdinaryMapNameRecords prior runtime map names differ only on ordinary cells without motorway gates; their runtime gates are generated from the plan."
}
Write-Output "Geometry comparison: none. Motorway assembly origins, yaws, leases and grid shifts are unchanged."
if ($ValidateOnly) { Write-Output 'Validation only: no files written.' }
