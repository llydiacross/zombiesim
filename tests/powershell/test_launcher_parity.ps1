param(
    [string]$CompiledBspPath,
    [ValidateSet('preview', 'city')][string]$CompiledProfile = 'preview'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$projectRoot = $testsRepoRoot
$skyboxPoses = @{}
foreach ($profile in @('preview', 'city')) {
    $path = Join-Path $projectRoot "celltemplates\launchers\zn_${profile}_start.vmf"
    $text = (Get-Content -Raw -LiteralPath $path) -replace "`r`n", "`n"
    $entities = [regex]::Matches($text, '(?ms)^entity\n\{.*?(?=^entity\n\{|^cameras\n\{)')
    $named = @{}
    $previewSkybox = $null
    $skyCameras = @()
    foreach ($entity in $entities) {
        if ($entity.Value -match '(?m)^\s*"classname" "sky_camera"') { $skyCameras += $entity.Value }
        $target = [regex]::Match($entity.Value, '(?m)^\s*"targetname" "([^"]+)"')
        if (-not $target.Success) { continue }
        $name = $target.Groups[1].Value
        if ($name -ieq 'preview_skybox') {
            if ($null -ne $previewSkybox) { throw "$profile has duplicate preview_skybox cameras" }
            $previewSkybox = $entity.Value
        }
        if ($name -in @('credits_camera', 'menu_camera', 'menu_globe', 'dancing_gman', 'create_character')) {
            if ($named.ContainsKey($name)) { throw "$profile has duplicate $name" }
            $named[$name] = $entity.Value
        }
    }
    foreach ($name in @('credits_camera', 'menu_camera', 'menu_globe', 'dancing_gman', 'create_character')) {
        if (-not $named.ContainsKey($name)) { throw "$profile is missing $name" }
    }
    foreach ($name in @('credits_camera', 'menu_camera')) {
        if ($named[$name] -notmatch '"classname" "point_camera"' -or
            $named[$name] -notmatch '"spawnflags" "1"' -or
            $named[$name] -notmatch '"FOV" "90"') {
            throw "$profile $name must be a Start Off point_camera with FOV 90"
        }
    }
    if ($named.create_character -notmatch '"classname" "point_camera"' -or
        $named.create_character -notmatch '"spawnflags" "1"') {
        throw "$profile create_character must be a Start Off point_camera"
    }
    foreach ($key in @('origin', 'angles', 'FOV')) {
        if ($named.create_character -notmatch ('"' + $key + '" "[^"]+"')) {
            throw "$profile create_character is missing $key"
        }
    }
    $creationId = [regex]::Match($named.create_character, '(?m)^\s*"id" "(\d+)"')
    if (-not $creationId.Success -or
        [regex]::Matches($text, '(?m)^\s*"id" "' + $creationId.Groups[1].Value + '"$').Count -ne 1) {
        throw "$profile create_character must have a unique Hammer ID"
    }
    if ($named.menu_camera -notmatch '"origin" "0 -160 112"' -or
        $named.menu_camera -notmatch '"angles" "0 90 0"' -or
        $named.menu_globe -notmatch '"classname" "info_target"' -or
        $named.menu_globe -notmatch '"origin" "96 32 112"') {
        throw "$profile menu poses no longer place the globe to the right of the north-facing view"
    }
    if ($named.dancing_gman -notmatch '"classname" "prop_ragdoll"') { throw "$profile G-Man must remain a ragdoll" }
    if (-not $previewSkybox -or $previewSkybox -notmatch '"classname" "point_camera"' -or
        $previewSkybox -notmatch '"spawnflags" "1"' -or $previewSkybox -notmatch '"FOV" "90"') {
        throw "$profile must have one Start Off preview_skybox point_camera with FOV 90"
    }
    if ($skyCameras.Count -ne 1) { throw "$profile must have exactly one sky_camera" }
    if ($profile -eq 'preview') {
        if ($skyCameras[0] -notmatch '(?m)^\s*"scale" "16"' -or
            $skyCameras[0] -notmatch '(?m)^\s*"origin" "-6976 1984 -142\.5"') {
            throw 'preview sky_camera must map the main island center and waterline onto the miniature ocean center at scale 16'
        }
    }
    $cameraValues = [regex]::Matches($previewSkybox, '(?m)^\s*"(classname|angles|FOV|spawnflags|targetname|origin)" "([^"]*)"')
    $skyboxPoses[$profile] = ($cameraValues | ForEach-Object {
        $_.Groups[1].Value + '=' + $_.Groups[2].Value
    }) -join "`n"
    $selector = [regex]::Matches($text, '(?m)^\s*"world_profile" "([^"]+)"')
    if ($selector.Count -ne 1 -or $selector[0].Groups[1].Value -ne $profile) {
        throw "$profile launcher has an incorrect world selector"
    }
}

if ($skyboxPoses.city -cne $skyboxPoses.preview) {
    throw 'Launcher skybox camera runtime poses differ between city and preview.'
}
Write-Output 'Launcher checks passed: menu and character-creation cameras in both profiles, one sky_camera per scene, aligned preview sky_camera, and matching Start Off preview_skybox poses. Authored room geometry is checked independently.'

if ($CompiledBspPath) {
    if (-not (Test-Path -LiteralPath $CompiledBspPath -PathType Leaf)) {
        throw "Compiled launcher BSP not found: $CompiledBspPath"
    }
    Import-Module (Join-Path $testsBinDirectory 'skybox_models.psm1') -Force
    $sourcePath = Join-Path $projectRoot "celltemplates\launchers\zn_${CompiledProfile}_start.vmf"
    $source = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -LiteralPath $sourcePath -Raw)).Children
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CompiledBspPath).Path)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'VBSP') {
        throw "Invalid launcher BSP: $CompiledBspPath"
    }
    $offset = [BitConverter]::ToInt32($bytes, 8)
    $length = [BitConverter]::ToInt32($bytes, 12)
    if ($offset -lt 0 -or $length -lt 1 -or [long]$offset + $length -gt $bytes.Length) {
        throw "Invalid launcher BSP entity lump: $CompiledBspPath"
    }
    $entities = [ZombieSim.Skybox.KeyValuesParser]::Parse(
        [Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)
    ).Children
    $authored = @($source | Where-Object { $_.Get('targetname') -eq 'create_character' })
    $compiled = @($entities | Where-Object { $_.Get('targetname') -eq 'create_character' })
    if ($authored.Count -ne 1 -or $compiled.Count -ne 1) {
        throw "$CompiledProfile launcher must have exactly one authored and compiled creation camera"
    }
    foreach ($key in @('classname', 'targetname', 'origin', 'angles', 'FOV', 'spawnflags')) {
        if ($authored[0].Get($key) -ne $compiled[0].Get($key)) {
            throw "$CompiledProfile compiled creation camera differs from its source: $key"
        }
    }
    Write-Output "Compiled $CompiledProfile launcher creation camera matches the authored pose."
}
