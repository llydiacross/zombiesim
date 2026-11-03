Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'skybox_models.psm1') -Force
$projectRoot = $testsRepoRoot
$fixtureRoot = Join-Path $projectRoot 'generated\skybox_tower_tests'
[System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$towerPath = Join-Path $projectRoot 'tiletemplates\buildings\tile_skyscraper_1aaa_2x.vmf'
$terrainPath = Join-Path $projectRoot 'tiletemplates\terrain\tile_dirt.vmf'
$mixedPath = Join-Path $fixtureRoot 'mixed.vmf'
$emptyPath = Join-Path $fixtureRoot 'without_tower.vmf'
$towerOnlyPath = Join-Path $fixtureRoot 'tower_only.vmf'
$destroyedPath = Join-Path $fixtureRoot 'destroyed_tower.vmf'

function New-TestInstance {
    param([string]$Path, [string]$Origin, [int]$Id)

    return "entity`r`n{`r`n`"id`" `"$Id`"`r`n`"classname`" `"func_instance`"`r`n`"file`" `"$Path`"`r`n`"origin`" `"$Origin`"`r`n`"angles`" `"0 90 0`"`r`n}`r`n"
}

$towerInstance = New-TestInstance $towerPath '640 -640 0' 1
$terrainInstance = New-TestInstance $terrainPath '6400 0 0' 2
$radioactiveTowerPath = Join-Path $projectRoot 'tiletemplates\buildings\tile_skyscraper_ra_2aa_2x.vmf'
$destroyedTowerPath = Join-Path $projectRoot 'tiletemplates\buildings\tile_skyscraper_destroyed_1a_2x.vmf'
$radioactivePath = Join-Path $fixtureRoot 'radioactive_tower.vmf'
$destroyedInstance = New-TestInstance $destroyedTowerPath '640 -640 0' 4
[System.IO.File]::WriteAllText($mixedPath, $towerInstance + $terrainInstance)
[System.IO.File]::WriteAllText($towerOnlyPath, $towerInstance)
[System.IO.File]::WriteAllText($emptyPath, $terrainInstance)
[System.IO.File]::WriteAllText($radioactivePath, (New-TestInstance $radioactiveTowerPath '640 -640 0' 3) + $terrainInstance)
$null = [System.IO.File]::WriteAllText($destroyedPath, $destroyedInstance + $terrainInstance)
$builder = [ZombieSim.Skybox.CellModelBuilder]::new(24)
$materials = [System.Collections.Generic.Dictionary[string, ZombieSim.Skybox.MaterialInfo]]::new()
foreach ($material in $builder.CollectMaterials([string[]]@($mixedPath, $radioactivePath, $destroyedPath))) {
    if ($materials.ContainsKey($material)) { continue }
    $info = [ZombieSim.Skybox.MaterialInfo]::new()
    $info.ModelMaterial = $material
    $info.Width = 256
    $info.Height = 256
    $materials.Add($material, $info)
}
$towers = $builder.BuildTowerParts($mixedPath, 1.0 / 16, $materials, 30000, 60)
$reference = $builder.BuildParts($towerOnlyPath, 1.0 / 16, $materials, 30000, 60)
$full = $builder.BuildParts($mixedPath, 1.0 / 16, $materials, 30000, 60)
$none = $builder.BuildTowerParts($emptyPath, 1.0 / 16, $materials, 30000, 60)
if ($towers.Count -eq 0 -or $towers.Count -ne $reference.Count -or $none.Count -ne 0) {
    throw 'Tower-only extraction must include towers and exclude ordinary terrain.'
}
$radioactiveTowers = $builder.BuildTowerParts($radioactivePath, 1.0 / 16, $materials, 30000, 60)
if ($radioactiveTowers.Count -eq 0) { throw 'Tower-only extraction must include radioactive tile_skyscraper_ra_* towers.' }
$destroyedTowers = $builder.BuildTowerParts($destroyedPath, 1.0 / 16, $materials, 30000, 60)
$destroyedReference = $builder.BuildParts($destroyedPath, 1.0 / 16, $materials, 30000, 60)
if ($destroyedTowers.Count -eq 0 -or $destroyedTowers.Count -ne $destroyedReference.Count) {
    throw 'Tower-only extraction must include destroyed tile_skyscraper_destroyed_* towers.'
}
for ($index = 0; $index -lt $towers.Count; $index++) {
    if ($towers[$index].Smd -cne $reference[$index].Smd) {
        throw 'Tower-only extraction must preserve exact instance transform, geometry, normals and UVs.'
    }
    if ($towers[$index].Max.Z -gt 4384.0 / 16 + 0.01) { throw 'Scaled tower height exceeds authored extent.' }
}
$towerTriangles = ($towers | Measure-Object Triangles -Sum).Sum
$fullTriangles = ($full | Measure-Object Triangles -Sum).Sum
if ($towerTriangles -ge $fullTriangles) { throw 'Mixed recipe must contain geometry excluded from tower-only output.' }
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'build_skybox_models.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw ($errors | Out-String) }
Write-Output "Skybox tower extraction passed: parts=$($towers.Count), towerTriangles=$towerTriangles, fullTriangles=$fullTriangles; transforms/UVs preserved, empty recipes excluded."
