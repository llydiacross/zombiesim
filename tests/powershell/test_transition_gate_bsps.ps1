param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$BuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'skybox_models.psm1') -Force
$maps = 0
$gates = 0
$landmarks = 0
$expectedLandmarks = 0

function Assert-SourceGateLayout {
    param([IO.FileInfo]$File, [object]$Source, [object[]]$GateEntities)

    $layoutPath = [IO.Path]::ChangeExtension($File.FullName, '.layout.json')
    if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) { return }
    $layout = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
    if ($null -eq $layout.PSObject.Properties['motorwayAssembly']) { return }
    $records = @($layout.motorwayAssembly.gates)
    if ($records.Count -eq 0) { throw "Motorway layout has no preserved gates: $layoutPath" }

    foreach ($record in $records) {
        $direction = [string]$record.direction
        $directionName = @{ N = 'NORTH'; E = 'EAST'; S = 'SOUTH'; W = 'WEST' }[$direction]
        $route = if ($null -ne $record.PSObject.Properties['route']) { [string]$record.route } else { 'motorway' }
        $directionGates = @($GateEntities | Where-Object {
            $_.Get('zm_transition_direction').ToUpperInvariant() -eq $directionName
        })
        $expectedCount = if ($route -eq 'motorway') { 2 } else { 1 }
        if ($directionGates.Count -ne $expectedCount) {
            throw "$($File.Name) $direction expected $expectedCount lane trigger(s); found $($directionGates.Count)."
        }
        $expectedOrigin = '{0} {1} {2}' -f $record.x, $record.y, ($record.deckZ + 20)
        foreach ($gate in $directionGates) {
            if ($gate.Get('origin') -ne $expectedOrigin) {
                throw "$($File.Name) $direction trigger origin differs from its trusted plan gate."
            }
        }
        if ($route -eq 'motorway') {
            $laneTargets = @($directionGates | ForEach-Object {
                $target = [regex]::Match([string]$_.Get('targetname'), "^zm_transition_gate_$direction`_lane(?<lane>[12])$")
                if (-not $target.Success -or $_.Get('zm_transition_lane') -ne $target.Groups['lane'].Value) {
                    throw "$($File.Name) $direction trigger is missing its matching lane tag."
                }
                [int]$target.Groups['lane'].Value
            } | Sort-Object)
            if (($laneTargets -join ',') -ne '1,2') { throw "$($File.Name) $direction does not publish exactly lanes 1 and 2." }
        } elseif ($directionGates[0].Get('targetname') -ne "zm_transition_gate_$direction" -or
            -not [string]::IsNullOrWhiteSpace($directionGates[0].Get('zm_transition_lane'))) {
            throw "$($File.Name) ordinary-road gate $direction must remain one untagged trigger."
        }
        $arrivalLane = $record.lanes[[int]$record.arrivalLane - 1]
        $arrivalName = "${directionName}_ENTRANCE"
        $arrival = @($Source.Children | Where-Object {
            $_.Get('classname') -eq 'info_landmark' -and $_.Get('targetname') -eq $arrivalName
        })
        if ($arrival.Count -ne 1 -or
            $arrival[0].Get('origin') -ne ('{0} {1} {2}' -f $arrivalLane.arrivalX, $arrivalLane.arrivalY, ($record.deckZ + 4))) {
            throw "$($File.Name) $direction arrival landmark differs from its trusted lane record."
        }
    }
}

foreach ($file in Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.vmf' -File) {
    $source = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -LiteralPath $file.FullName -Raw))
    $expected = @($source.Children | Where-Object {
        $_.Get('classname') -eq 'trigger_multiple' -and $_.Get('targetname') -match '^zm_transition_gate_[NESW](?:_lane[12])?$'
    })
    if ($expected.Count -eq 0) { continue }
    Assert-SourceGateLayout $file $source @($expected)
    $bsp = Join-Path $BuildDirectory ([IO.Path]::ChangeExtension($file.Name, '.bsp'))
    $bytes = [IO.File]::ReadAllBytes($bsp)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'VBSP') {
        throw "Invalid gate fixture BSP: $bsp"
    }
    $offset = [BitConverter]::ToInt32($bytes, 8)
    $length = [BitConverter]::ToInt32($bytes, 12)
    if ($offset -lt 0 -or $length -lt 1 -or [long]$offset + $length -gt $bytes.Length) {
        throw "Invalid BSP entity lump: $bsp"
    }
    $entities = [ZombieSim.Skybox.KeyValuesParser]::Parse(
        [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
    ).Children
    $arrivalNames = @{}
    foreach ($gate in @($expected | Where-Object { $_.Get('classname') -eq 'trigger_multiple' })) {
        $direction = $gate.Get('zm_transition_direction').ToUpperInvariant()
        $arrivalName = "${direction}_ENTRANCE"
        if ($arrivalNames.ContainsKey($arrivalName)) {
            $gates++
            continue
        }
        $arrival = @($source.Children | Where-Object { $_.Get('classname') -eq 'info_landmark' -and $_.Get('targetname') -eq $arrivalName })
        if ($arrival.Count -ne 1) { throw "Missing/duplicated source arrival $arrivalName in $($file.Name)" }
        $expected += $arrival
        $arrivalNames[$arrivalName] = $true
        $expectedLandmarks++
        $gates++
    }
    foreach ($entity in $expected) {
        $name = $entity.Get('targetname')
        $matches = @($entities | Where-Object { $_.Get('targetname') -eq $name })
        if ($matches.Count -ne 1) { throw "Missing/duplicated compiled gate entity $name in $bsp" }
        foreach ($key in 'classname', 'origin', 'angles', 'model', 'zm_transition_gate', 'zm_transition_direction', 'zm_transition_lane', 'zm_transition_mode') {
            if ($key -eq 'model' -and $entity.Get('classname') -eq 'trigger_multiple') { continue }
            $value = $entity.Get($key)
            if (-not [string]::IsNullOrWhiteSpace($value) -and $matches[0].Get($key) -ne $value) {
                throw "Compiled gate entity $name changed $key in $bsp"
            }
        }
        if ($entity.Get('classname') -eq 'trigger_multiple' -and $matches[0].Get('model') -notmatch '^\*\d+$') {
            throw "Compiled gate $name has no brush model in $bsp"
        }
        if ($entity.Get('classname') -eq 'info_landmark') { $landmarks++ }
    }
    $maps++
}
if ($maps -eq 0 -or $gates -eq 0 -or $landmarks -ne $expectedLandmarks) {
    throw "Incomplete compiled gate coverage: $maps maps, $gates gates, $landmarks arrivals"
}
Write-Output "Compiled gate checks: $maps maps, $gates gates and $landmarks arrivals retain source placement."
