Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$updateScript = Join-Path $testsRoot 'bin\update_preview_runtime_map_names.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("zombiesim_runtime_map_names_" + [guid]::NewGuid().ToString('N'))
$passed = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Preview runtime map-name checks: $Message" }
    $script:passed++
}

function Get-CellSignatureWithoutMap {
    param([object]$Cell)

    $fields = [ordered]@{}
    foreach ($property in $Cell.PSObject.Properties) {
        if ($property.Name -ne 'map') { $fields[$property.Name] = $property.Value }
    }
    return $fields | ConvertTo-Json -Depth 30 -Compress
}

try {
    $runtimePath = Join-Path $fixtureRoot 'base-world.json'
    $planPath = Join-Path $fixtureRoot 'partial-plan.json'
    $outputPath = Join-Path $fixtureRoot 'updated-world.json'
    $badPlanPath = Join-Path $fixtureRoot 'bad-plan.json'
    $badOutputPath = Join-Path $fixtureRoot 'bad-output.json'
    $skyboxPath = Join-Path $fixtureRoot 'skybox.json'
    $skyboxOutputPath = Join-Path $fixtureRoot 'updated-skybox.json'
    $badSkyboxOutputPath = Join-Path $fixtureRoot 'bad-skybox.json'
    $buildDirectory = Join-Path $fixtureRoot 'build'
    $contentMapDirectory = Join-Path $fixtureRoot 'content-maps'
    $engineMapDirectory = Join-Path $fixtureRoot 'engine-maps'
    $sourceDirectory = Join-Path $fixtureRoot 'source'
    $cellBounds = [ordered]@{
        revision = 2
        tileSize = 640
        coreTileGridSize = 5
        coreHalfExtent = 1600
        traversableHalfExtent = 1600
        visualHalfExtent = 2880
        neighbourPitch = 5760
        coastContactHalfExtent = 2240
        playableCeiling = 3328
    }
    foreach ($directory in @($buildDirectory, $contentMapDirectory, $engineMapDirectory, $sourceDirectory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $targetCells = @(
        [pscustomobject]@{
            x = 17; y = 4; map = 'zz_preview_a30b0e90c7e2'
            entrances = @('E', 'N', 'S', 'W')
        },
        [pscustomobject]@{
            x = 22; y = 18; map = 'zz_preview_74c1b0c24754'
            entrances = @('E', 'S', 'W')
        }
    )
    $runtimeCells = [System.Collections.Generic.List[object]]::new()
    for ($id = 0; $id -lt 576; $id++) {
        $cell = [ordered]@{
            id = $id
            map = "zz_preview_old_$id"
            waterSides = @()
            topology = 'terrain'
            entrances = @()
            motorwayGates = @()
            fixtureTag = "keep-$id"
        }
        foreach ($target in $targetCells) {
            if ($id -eq ($target.y * 24 + $target.x)) {
                $cell.map = "zz_preview_old_$id"
                $cell.topology = 'motorway-straight'
                $cell.entrances = @($target.entrances)
                $cell.motorwayGates = @($target.entrances | ForEach-Object {
                    [ordered]@{ direction = $_ }
                })
            }
        }
        $runtimeCells.Add($cell)
    }

    $runtime = [ordered]@{
        schemaVersion = 1
        world = [ordered]@{
            profileId = 'preview'
            seed = 1337
            grid = @(24, 24)
            mapManifestSha256 = ('a' * 64)
            templatePlanSha256 = ('b' * 64)
            cellBounds = $cellBounds
        }
        cells = @($runtimeCells)
    }
    [IO.File]::WriteAllText($runtimePath, ($runtime | ConvertTo-Json -Depth 30 -Compress),
        [Text.UTF8Encoding]::new($false))

    $skyGeometry = [ordered]@{}
    $skyRecipes = [ordered]@{}
    $skySnow = [ordered]@{}
    $skyTowers = [ordered]@{}
    $skyDetails = [ordered]@{}
    foreach ($target in $targetCells) {
        $id = $target.y * 24 + $target.x
        $oldName = "zz_preview_old_$id"
        $skyGeometry[$oldName] = [ordered]@{
            vmfSha256 = ('c' * 64)
            waterSides = @()
            coastHalfExtent = 2240
            visualHalfExtent = 2880
        }
        $skyRecipes[$oldName] = @("models/zombiesim/skybox/cells/${oldName}_p0.mdl")
        $skySnow[$oldName] = @("models/zombiesim/skybox/cells/${oldName}_snow_p0.mdl")
        $skyTowers[$oldName] = @("models/zombiesim/skybox/cells/${oldName}_tower_p0.mdl")
        $skyDetails[$oldName] = [ordered]@{ props = @(); fires = @(); edgeFires = @() }
    }
    $skybox = [ordered]@{
        schemaVersion = 2
        profile = 'preview'
        cellBounds = $cellBounds
        templatePlanSha256 = ('b' * 64)
        geometry = $skyGeometry
        recipes = $skyRecipes
        snow = $skySnow
        towers = $skyTowers
        detail = [ordered]@{ models = @(); recipes = $skyDetails }
    }
    [IO.File]::WriteAllText($skyboxPath, ($skybox | ConvertTo-Json -Depth 30 -Compress),
        [Text.UTF8Encoding]::new($false))

    $planCells = [System.Collections.Generic.List[object]]::new()
    foreach ($target in $targetCells) {
        $vmfName = "$($target.map).vmf"
        $vmfPath = Join-Path $sourceDirectory $vmfName
        [IO.File]::WriteAllText($vmfPath, "fixture $vmfName", [Text.UTF8Encoding]::new($false))
        $vmfHash = (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText([IO.Path]::ChangeExtension($vmfPath, '.layout.json'),
            (@{
                vmfSha256 = $vmfHash
                waterSides = @()
                bounds = @{ revision = 2; coastContactHalfExtent = 2240; visualHalfExtent = 2880 }
            } | ConvertTo-Json -Depth 5 -Compress), [Text.UTF8Encoding]::new($false))
        foreach ($directory in @($buildDirectory, $contentMapDirectory, $engineMapDirectory)) {
            [IO.File]::WriteAllText((Join-Path $directory "$($target.map).bsp"),
                "fixture $($target.map)", [Text.UTF8Encoding]::new($false))
        }
        $planCells.Add([ordered]@{
            x = $target.x
            y = $target.y
            topology = 'motorway-straight'
            skyboxOceanSides = @()
            activeEntrances = @($target.entrances)
            gateDirections = @($target.entrances)
            cellTemplateFilename = $vmfName
        })
    }

    $plan = [ordered]@{
        schemaVersion = 2
        mapSeed = 1337
        mapGridCells = 24
        cellBounds = $cellBounds
        cellDirectory = $sourceDirectory
        cells = @($planCells)
    }
    [IO.File]::WriteAllText($planPath, ($plan | ConvertTo-Json -Depth 30 -Compress),
        [Text.UTF8Encoding]::new($false))

    & $updateScript -PlanData $planPath -RuntimeWorldData $runtimePath -BuildDirectory $buildDirectory `
        -ContentMapDirectory $contentMapDirectory -EngineMapDirectory $engineMapDirectory `
        -Output $outputPath -SkyboxManifest $skyboxPath -SkyboxOutput $skyboxOutputPath `
        -WorldProfile preview | Out-Null

    $updated = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
    $baseAfter = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
    $updatedSkybox = Get-Content -LiteralPath $skyboxOutputPath -Raw | ConvertFrom-Json
    $targetNamesCorrect = $updated.cells[113].map -eq 'zz_preview_a30b0e90c7e2' `
        -and $updated.cells[454].map -eq 'zz_preview_74c1b0c24754'
    Assert $targetNamesCorrect 'updates the two selected logical cells.'
    $sourceUnchanged = $baseAfter.cells[113].map -eq 'zz_preview_old_113' `
        -and $baseAfter.cells[454].map -eq 'zz_preview_old_454'
    Assert $sourceUnchanged 'does not modify the source runtime export.'
    $hashesPreserved = $updated.world.templatePlanSha256 -eq ('b' * 64) `
        -and $updated.world.mapManifestSha256 -eq ('a' * 64)
    Assert $hashesPreserved 'preserves the installed revision hashes.'
    $skyboxAliasesCorrect = $updatedSkybox.templatePlanSha256 -eq ('b' * 64)
    foreach ($target in $targetCells) {
        $id = $target.y * 24 + $target.x
        $oldName = "zz_preview_old_$id"
        $newName = [string]$target.map
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $sourceDirectory "$newName.vmf") -Algorithm SHA256).Hash.ToLowerInvariant()
        $newGeometry = $updatedSkybox.geometry.PSObject.Properties[$newName].Value
        $newModels = $updatedSkybox.recipes.PSObject.Properties[$newName].Value
        $oldModels = $skyRecipes[$oldName]
        $skyboxAliasesCorrect = $skyboxAliasesCorrect -and
            $newGeometry.vmfSha256 -eq $sourceHash -and @($newGeometry.waterSides).Count -eq 0 -and
            $newGeometry.coastHalfExtent -eq 2240 -and $newGeometry.visualHalfExtent -eq 2880 -and
            (($newModels | ConvertTo-Json -Compress) -ceq ($oldModels | ConvertTo-Json -Compress))
    }
    Assert $skyboxAliasesCorrect 'adds fresh footprints and preserves the previous model records under each new map name.'
    $firstCellUnchanged = (Get-CellSignatureWithoutMap $updated.cells[0]) -ceq
        (Get-CellSignatureWithoutMap $baseAfter.cells[0])
    Assert $firstCellUnchanged 'preserves non-target cell data.'
    $allOtherCellsUnchanged = $true
    foreach ($id in 0..575) {
        if ($id -in @(113, 454)) { continue }
        $cellUnchanged = (Get-CellSignatureWithoutMap $updated.cells[$id]) -ceq
            (Get-CellSignatureWithoutMap $baseAfter.cells[$id])
        if (-not $cellUnchanged) {
            $allOtherCellsUnchanged = $false
            break
        }
    }
    Assert $allOtherCellsUnchanged 'changes no other runtime cell records.'

    $badPlan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $badPlan.cells[0].topology = 'ordinary-road'
    [IO.File]::WriteAllText($badPlanPath, ($badPlan | ConvertTo-Json -Depth 30 -Compress),
        [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        & $updateScript -PlanData $badPlanPath -RuntimeWorldData $runtimePath -BuildDirectory $buildDirectory `
            -ContentMapDirectory $contentMapDirectory -EngineMapDirectory $engineMapDirectory `
            -Output $badOutputPath -SkyboxManifest $skyboxPath -SkyboxOutput $badSkyboxOutputPath `
            -WorldProfile preview | Out-Null
    } catch {
        $rejected = $true
    }
    Assert $rejected 'rejects a map update whose topology differs from the runtime cell.'
    Assert (-not (Test-Path -LiteralPath $badOutputPath)) 'writes no candidate after validation failure.'
    Assert (-not (Test-Path -LiteralPath $badSkyboxOutputPath)) 'writes no skyline candidate after validation failure.'

    Write-Output "Preview runtime map-name checks: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
