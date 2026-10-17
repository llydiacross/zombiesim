Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway survey: $Message" }
    $script:passed++
}
$path = Join-Path ([System.IO.Path]::GetTempPath()) ("zombiesim-motorway-survey-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $summary = @(& (Join-Path $testsBinDirectory 'survey_motorway_templates.ps1') -WorldProfile preview -Output $path)
    $report = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    Assert ($summary.Count -eq 8 -and $report.pieces.Count -eq 8) 'Exactly eight saved wide sources surveyed.'
    Assert ($report.profile -eq 'preview' -and $report.schemaVersion -eq 1) 'Resolved preview profile and survey schema.'
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    & (Join-Path $testsBinDirectory 'survey_motorway_templates.ps1') -WorldProfile preview -Output $path | Out-Null
    Assert ($hash -ceq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) 'Repeated survey is byte-identical.'
    foreach ($piece in $report.pieces) {
        Assert ($piece.sha256 -ceq (Get-FileHash -LiteralPath $piece.source -Algorithm SHA256).Hash) 'Survey never changes a source asset.'
        Assert ($piece.faces.Count -eq $piece.faceCount -and $piece.solidCount -gt 0) 'Complete face records and solid count.'
        Assert ($piece.ports.Count -eq 0 -and $piece.portsStatus -eq 'requires_authored_and_Hammer_review') 'No inferred ports or compiled collision claims.'
        foreach ($face in $piece.faces) {
            Assert ($face.vertices.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($face.material)) 'Every saved face retains winding/material evidence.'
        }
    }
    $straight = $report.pieces[0]
    Assert ($null -eq $straight.namedFootprint.width -and -not $straight.namedFootprint.verified) 'Unsuffixed dimensions are not guessed from filenames.'
    Assert ($straight.windingBounds.x.min -eq -960 -and $straight.windingBounds.x.max -eq 960 -and $straight.windingBounds.y.min -eq -320 -and $straight.windingBounds.y.max -eq 320) 'Straight saved winding envelope is 1920 by 640.'
    foreach ($side in @('120', '126', '252', '258')) {
        $face = @($straight.faces | Where-Object sideId -eq $side)
        Assert ($face.Count -eq 1 -and $face[0].horizontal -and $face[0].vertices[0].z -eq 68 -and $face[0].material -eq 'CONCRETE/CONCRETEFLOOR037A') "Straight carriageway face $side remains at authored Z68."
    }
    $bridge = $report.pieces[1]
    foreach ($side in @('642', '690', '738')) {
        $face = @($bridge.faces | Where-Object sideId -eq $side)
        Assert ($face.Count -eq 1 -and $face[0].horizontal -and $face[0].vertices[0].z -eq 196.057) "Crossing road face $side retains the user-approved revised Z196.057."
    }
    $sizes = @(@(5, 3), @(6, 3), @(6, 3), @(3, 3), @(3, 4), @(3, 4))
    for ($index = 2; $index -lt 8; $index++) {
        Assert ($report.pieces[$index].namedFootprint.width -eq $sizes[$index - 2][0] -and $report.pieces[$index].namedFootprint.height -eq $sizes[$index - 2][1]) 'Rectangular suffix is parsed without square clamping.'
    }
    Assert ($report.pieces[5].windingBounds.x.max -eq 1120 -and $report.pieces[5].windingBounds.y.max -eq 992) 'Deadend overhang remains visible rather than clipped to nominal footprint.'
    Assert ($report.pieces[7].windingBounds.y.min -eq -1296) 'Dual-ramp overhang remains visible rather than clipped to nominal footprint.'
    $straightPorts = @(Get-ZMMotorwaySurfacePorts $straight)
    $bridgePorts = @(Get-ZMMotorwaySurfacePorts $bridge)
    Assert ($straightPorts.Count -eq 4 -and $bridgePorts.Count -eq 6) 'Surface contracts include both motorway carriageways and the elevated crossing road.'
    foreach ($port in $straightPorts) {
        Assert ($port.width -eq 416 -and $port.position.z -eq 68 -and $port.grade -eq 0) 'Straight ports use measured floor width/height, not legacy offsets.'
        Assert ($port.position.x -eq $(if ($port.id -like '*west_carriageway') { -512 } else { 528 })) 'Authored carriageway asymmetry survives port extraction.'
    }
    foreach ($port in @($bridgePorts | Where-Object route -eq road)) {
        Assert ($port.width -eq 256 -and $port.position.z -eq 196.057 -and $port.position.y -eq 0) 'Bridge ports describe the approved central road floor, not raised curb tops.'
        Assert ([Math]::Abs($port.position.x) -eq 960) 'Bridge road mouths use authored exterior edges.'
    }
    $north = @($straightPorts | Where-Object id -eq 'N/west_carriageway')[0]
    $south = @($straightPorts | Where-Object id -eq 'S/west_carriageway')[0]
    foreach ($yaw in @(0, 90, 180, 270)) {
        $fixedOrigin = [pscustomobject]@{ x = 123; y = -456; z = 0 }
        $fixed = Convert-ZMMotorwayPort $north $yaw $fixedOrigin
        $translation = Resolve-ZMMotorwayPortTranslation $fixed $south $yaw 0
        $joined = Convert-ZMMotorwayPort $south $yaw $translation
        Assert ($joined.position.x -eq $fixed.position.x -and $joined.position.y -eq $fixed.position.y -and $joined.position.z -eq $fixed.position.z) 'Solved translation joins measured carriageway floors exactly in every rotation.'
        $eastNorth = @($straightPorts | Where-Object id -eq 'N/east_carriageway')[0]
        $eastSouth = @($straightPorts | Where-Object id -eq 'S/east_carriageway')[0]
        $eastFixed = Convert-ZMMotorwayPort $eastNorth $yaw $fixedOrigin
        $eastJoined = Convert-ZMMotorwayPort $eastSouth $yaw $translation
        Assert ($eastFixed.position.x -eq $eastJoined.position.x -and $eastFixed.position.y -eq $eastJoined.position.y) 'One translation simultaneously connects both carriageways.'
        $bridgeSouth = @($bridgePorts | Where-Object id -eq 'S/west_carriageway')[0]
        $bridgeJoined = Convert-ZMMotorwayPort $bridgeSouth $yaw $translation
        Assert ($bridgeJoined.position.x -eq $fixed.position.x -and $bridgeJoined.position.y -eq $fixed.position.y -and $bridgeJoined.position.z -eq $fixed.position.z) 'Straight-to-bridge motorway seam preserves both geometry and elevation.'
    }
    foreach ($case in @(
        @{ change = 'width'; value = 400; pattern = '*surface widths differ*' },
        @{ change = 'route'; value = 'road'; pattern = '*route types differ*' },
        @{ change = 'outward'; value = 'N'; pattern = '*headings must oppose*' },
        @{ change = 'grade'; value = 0.1; pattern = '*grades do not match*' }
    )) {
        $bad = $south | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $bad.($case.change) = $case.value
        $rejected = $false
        try { Resolve-ZMMotorwayPortTranslation $north $bad 0 0 | Out-Null } catch {
            if ($_.Exception.Message -notlike $case.pattern) { throw }
            $rejected = $true
        }
        Assert $rejected 'Incompatible ports fail explicitly instead of scaling/reorienting.'
    }
    $badDeck = $south | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $badDeck.position.z = 196
    $rejected = $false
    try { Resolve-ZMMotorwayPortTranslation $north $badDeck 0 0 | Out-Null } catch {
        if ($_.Exception.Message -notlike '*deck heights differ*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Vertical displacement cannot hide a deck mismatch.'
    $rejected = $false
    try { Get-ZMMotorwaySurfacePorts $report.pieces[2] | Out-Null } catch {
        if ($_.Exception.Message -notlike '*no inferred connector fallback*') { throw }
        $rejected = $true
    }
    Assert $rejected 'Unrecorded complex ports never fall back to bounding-box guesses.'
    $mouthCounts = @(2, 4, 2, 4, 3, 1, 3, 4)
    for ($pieceIndex = 0; $pieceIndex -lt $report.pieces.Count; $pieceIndex++) {
        $registry = Get-ZMMotorwayMouthRegistry $report.pieces[$pieceIndex]
        Assert ($registry.mouths.Count -eq $mouthCounts[$pieceIndex]) 'All eight explicit mouth lists retain topology, including a single terminal mouth.'
        Assert ($registry.sha256 -ceq $report.pieces[$pieceIndex].sha256) 'Registry retains measured source provenance.'
        foreach ($mouth in $registry.mouths) {
            Assert ($mouth.lanes.Count -eq $(if ($mouth.route -eq 'motorway') { 2 } else { 1 })) 'Each motorway mouth has two carriageways; road mouths remain distinct.'
            foreach ($port in $mouth.lanes) {
                Assert ($port.width -gt 0 -and $port.edges.Count -eq $port.sourceSides.Count) 'Every port retains source-backed finite width and edge provenance.'
                foreach ($yaw in @(0, 90, 180, 270)) {
                    $origin = [pscustomobject]@{ x = 0; y = 0; z = 0 }
                    $transformed = Convert-ZMMotorwayPort $port $yaw $origin
                    $restored = Convert-ZMMotorwayPort $transformed ((360 - $yaw) % 360) $origin
                    Assert ($restored.position.x -eq $port.position.x -and $restored.position.y -eq $port.position.y -and $restored.position.z -eq $port.position.z -and $restored.outward -eq $port.outward) 'Every complex port round-trips all rotations without snapping fractional coordinates.'
                    Assert ($transformed.width -eq $port.width -and $transformed.grade -eq $port.grade) 'Rotations preserve measured width and grade.'
                }
            }
        }
    }
    $cornerMouths = (Get-ZMMotorwayMouthRegistry $report.pieces[2]).mouths
    $east = @($cornerMouths | Where-Object outward -eq E)[0]
    Assert ($east.lanes[1].position.y - $east.lanes[0].position.y -eq 1024) 'Corner mouth preserves the measured pair separation rather than assuming straight separation1040.'
    $southCorner = @($cornerMouths | Where-Object outward -eq S)[0]
    Assert (-not $southCorner.lanes[1].planarCardinal) 'Curved decimal mouth is explicit, not a false cardinal seam.'
    foreach ($pieceIndex in @(6, 7)) {
        $roads = @((Get-ZMMotorwayMouthRegistry $report.pieces[$pieceIndex]).mouths | Where-Object route -eq road)
        foreach ($mouth in $roads) {
            $expectedGrade = if ($pieceIndex -eq 6) { -112.0 / 192 } else { -0.5 }
            $expectedHeight = if ($pieceIndex -eq 6) { 80 } else { 96 }
            Assert ($mouth.lanes[0].grade -eq $expectedGrade -and $mouth.lanes[0].position.z -eq $expectedHeight) 'Ramp grade/deck retain the user-approved single80/dual96 source revision without ordinary-road correction.'
        }
    }
    foreach ($mutation in @('missing', 'material', 'displacement', 'nonfinite')) {
        $bad = $straight | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $face = @($bad.faces | Where-Object sideId -eq '120')[0]
        switch ($mutation) {
            'missing' { $bad.faces = @($bad.faces | Where-Object sideId -ne '120') }
            'material' { $face.material = 'TOOLS/TOOLSNODRAW' }
            'displacement' { $face.displacement = $true }
            'nonfinite' { $face.vertices[0].x = [double]::NaN }
        }
        $rejected = $false
        try { Get-ZMMotorwayMouthRegistry $bad | Out-Null } catch {
            if ($_.Exception.Message -notlike '*mouth face*changed/missing*' -and $_.Exception.Message -notlike '*non-finite*') { throw }
            $rejected = $true
        }
        Assert $rejected "Invalid $mutation mouth evidence fails explicitly."
    }
}
finally {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
Write-Host "Motorway survey: $passed assertions passed; eight sources unchanged. All-family measured mouths verified; physical assemblies remain integration gates."
