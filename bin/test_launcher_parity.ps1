Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$texts = @{}
foreach ($profile in @('preview', 'city')) {
    $path = Join-Path $projectRoot "celltemplates\launchers\zn_${profile}_start.vmf"
    $text = (Get-Content -Raw -LiteralPath $path) -replace "`r`n", "`n"
    $entities = [regex]::Matches($text, '(?ms)^entity\n\{.*?(?=^entity\n\{|^cameras\n\{)')
    $named = @{}
    foreach ($entity in $entities) {
        $target = [regex]::Match($entity.Value, '(?m)^\s*"targetname" "([^"]+)"')
        if (-not $target.Success) { continue }
        $name = $target.Groups[1].Value
        if ($name -in @('credits_camera', 'menu_camera', 'menu_globe', 'dancing_gman')) {
            if ($named.ContainsKey($name)) { throw "$profile has duplicate $name" }
            $named[$name] = $entity.Value
        }
    }
    foreach ($name in @('credits_camera', 'menu_camera', 'menu_globe', 'dancing_gman')) {
        if (-not $named.ContainsKey($name)) { throw "$profile is missing $name" }
    }
    foreach ($name in @('credits_camera', 'menu_camera')) {
        if ($named[$name] -notmatch '"classname" "point_camera"' -or
            $named[$name] -notmatch '"spawnflags" "1"' -or
            $named[$name] -notmatch '"FOV" "90"') {
            throw "$profile $name must be a Start Off point_camera with FOV 90"
        }
    }
    if ($named.menu_camera -notmatch '"origin" "0 -160 112"' -or
        $named.menu_camera -notmatch '"angles" "0 90 0"' -or
        $named.menu_globe -notmatch '"classname" "info_target"' -or
        $named.menu_globe -notmatch '"origin" "96 32 112"') {
        throw "$profile menu poses no longer place the globe to the right of the north-facing view"
    }
    if ($named.dancing_gman -notmatch '"classname" "prop_ragdoll"') { throw "$profile G-Man must remain a ragdoll" }
    $selector = [regex]::Matches($text, '(?m)^\s*"world_profile" "([^"]+)"')
    if ($selector.Count -ne 1 -or $selector[0].Groups[1].Value -ne $profile) {
        throw "$profile launcher has an incorrect world selector"
    }
    $texts[$profile] = $text
}

$normalized = $texts.city.Replace('"world_profile" "city"', '"world_profile" "PROFILE"')
$preview = $texts.preview.Replace('"world_profile" "preview"', '"world_profile" "PROFILE"')
if ($normalized -cne $preview) { throw 'Launcher VMFs differ beyond world_profile; check scene and dance-rig parity.' }
Write-Output 'Launcher parity passed: four named scene entities, Start Off cameras, right-side globe, identical VMFs except world_profile.'
