param([switch]$Compile)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$output = Join-Path $root 'generated\signs_preview\zoo'
$null = New-Item -ItemType Directory -Force -Path $output
$name = 'zn_dev_sign_zoo'
$vmfPath = Join-Path $output "$name.vmf"
$catalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\zombiesim_signs_preview.json') -Raw | ConvertFrom-Json
$stations = @(
    @{ variant = 'freestanding'; x = -640; y = 256; z = 0; yaw = 0 },
    @{ variant = 'panel'; x = 0; y = 256; z = 144; yaw = 0 },
    @{ variant = 'illuminated'; x = 640; y = 256; z = 0; yaw = 0 },
    @{ variant = 'wall'; x = -640; y = -607.5; z = 192; yaw = 180 },
    @{ variant = 'print'; x = 0; y = -607.5; z = 192; yaw = 180 },
    @{ variant = 'poster'; x = 640; y = -607.5; z = 192; yaw = 180 }
)
$script:nextId = 2
function New-ZooEntity([System.Collections.IDictionary]$Properties) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("entity`r`n{`r`n    `"id`" `"$script:nextId`"")
    $script:nextId++
    foreach ($key in $Properties.Keys) { $lines.Add(('    "{0}" "{1}"' -f $key, $Properties[$key])) }
    $lines.Add('}')
    return $lines -join "`r`n"
}
function New-ZooBox([int]$X0, [int]$Y0, [int]$Z0, [int]$X1, [int]$Y1, [int]$Z1) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("solid`r`n{`r`n    `"id`" `"$script:nextId`"")
    $script:nextId++
    $planes = @(
        "($X0 $Y0 $Z1) ($X0 $Y1 $Z1) ($X1 $Y1 $Z1)",
        "($X1 $Y1 $Z0) ($X0 $Y1 $Z0) ($X0 $Y0 $Z0)",
        "($X0 $Y0 $Z0) ($X0 $Y1 $Z0) ($X0 $Y1 $Z1)",
        "($X1 $Y1 $Z0) ($X1 $Y0 $Z0) ($X1 $Y0 $Z1)",
        "($X1 $Y0 $Z0) ($X0 $Y0 $Z0) ($X0 $Y0 $Z1)",
        "($X0 $Y1 $Z0) ($X1 $Y1 $Z0) ($X1 $Y1 $Z1)"
    )
    for ($i = 0; $i -lt $planes.Count; $i++) {
        $u = if ($i -lt 2 -or $i -gt 3) { '[1 0 0 0] 0.25' } else { '[0 1 0 0] 0.25' }
        $v = if ($i -lt 2) { '[0 -1 0 0] 0.25' } else { '[0 0 -1 0] 0.25' }
        $lines.Add(@"
    side
    {
        "id" "$script:nextId"
        "plane" "$($planes[$i])"
        "material" "concrete/concretefloor037a"
        "uaxis" "$u"
        "vaxis" "$v"
        "rotation" "0"
        "lightmapscale" "16"
        "smoothing_groups" "0"
    }
"@)
        $script:nextId++
    }
    $lines.Add('}')
    return $lines -join "`r`n"
}
$brushes = @(
    (New-ZooBox -1024 -640 -32 1024 640 0),
    (New-ZooBox -1024 -640 512 1024 640 544),
    (New-ZooBox -1056 -640 -32 -1024 640 544),
    (New-ZooBox 1024 -640 -32 1056 640 544),
    (New-ZooBox -1056 -640 -32 1056 -608 544),
    (New-ZooBox -1056 608 -32 1056 640 544),
    (New-ZooBox -152 280 0 152 304 320)
)
$entities = [System.Collections.Generic.List[string]]::new()
foreach ($station in $stations) {
    $variant = $catalog.variants.PSObject.Properties[$station.variant]
    if ($null -eq $variant) { throw "Sign catalog is missing $($station.variant)." }
    $modelName = [System.IO.Path]::GetFileNameWithoutExtension([string]$variant.Value.model)
    $prefabPath = Join-Path $root "generated\signs_preview\prefabs\$modelName.vmf"
    $prefab = Get-Content -LiteralPath $prefabPath -Raw
    $blocks = [regex]::Matches($prefab, '(?ms)^entity\s*\{([^{}]*)\}')
    $expectedCount = if ($station.variant -eq 'illuminated') { 2 } else { 1 }
    if ($blocks.Count -ne $expectedCount) { throw "Unexpected sign prefab entities: $prefabPath" }
    foreach ($block in $blocks) {
        $properties = [ordered]@{}
        foreach ($pair in [regex]::Matches($block.Groups[1].Value, '"([^"]+)"\s+"([^"]*)"')) {
            if ($pair.Groups[1].Value -ne 'id') { $properties[$pair.Groups[1].Value] = $pair.Groups[2].Value }
        }
        $origin = @($properties.origin -split ' ' | ForEach-Object { [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) })
        $radians = $station.yaw * [math]::PI / 180
        $x = $station.x + $origin[0] * [math]::Cos($radians) - $origin[1] * [math]::Sin($radians)
        $y = $station.y + $origin[0] * [math]::Sin($radians) + $origin[1] * [math]::Cos($radians)
        $properties.origin = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0} {1} {2}', $x, $y, ($station.z + $origin[2]))
        $angles = $properties.angles -split ' '
        $properties.angles = "$($angles[0]) $([int]$angles[1] + $station.yaw) $($angles[2])"
        $properties.targetname = "sign_zoo_$($station.variant)_$($properties.classname)"
        $entities.Add((New-ZooEntity $properties))
    }
}
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'info_player_start'; origin = '0 -192 16'; angles = '0 90 0' })))
foreach ($x in -640, 0) {
    $entities.Add((New-ZooEntity ([ordered]@{ classname = 'light'; origin = "$x 0 400"; _light = '225 235 255 180'; _quadratic_attn = '1' })))
}
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'light'; origin = '0 -448 352'; _light = '255 238 208 140'; _quadratic_attn = '1' })))
$vmf = @"
versioninfo
{
    "editorversion" "400"
    "editorbuild" "8871"
    "mapversion" "1"
    "formatversion" "100"
    "prefab" "0"
}
world
{
    "id" "1"
    "classname" "worldspawn"
    "mapversion" "1"
    "skyname" "painted"
$($brushes -join "`r`n")
}
$($entities -join "`r`n")
cameras
{
    "activecamera" "0"
    camera
    {
        "position" "[0 -192 128]"
        "look" "[0 256 208]"
    }
}
"@
$utf8 = [System.Text.UTF8Encoding]::new($false)
if (-not (Test-Path -LiteralPath $vmfPath) -or [System.IO.File]::ReadAllText($vmfPath) -ne $vmf) {
    [System.IO.File]::WriteAllText($vmfPath, $vmf, $utf8)
}
[System.IO.File]::WriteAllText((Join-Path $output 'layout.json'), ($stations | ConvertTo-Json), $utf8)
& (Join-Path $PSScriptRoot 'stage_sign_assets.ps1')
if (-not $?) { throw 'Development sign staging failed.' }
Write-Host "Generated six-variant Hammer showroom: $vmfPath"
& (Join-Path $PSScriptRoot 'test_sign_zoo.ps1')
if (-not $?) { throw 'Sign zoo structural/staging regressions failed.' }
if (-not $Compile) { return }

$gameDirectory = Split-Path -Parent (Split-Path -Parent $root)
$compilerDirectory = Join-Path (Split-Path -Parent $gameDirectory) 'bin'
$bspPath = Join-Path $output "$name.bsp"
$dependencies = @($vmfPath, $PSCommandPath, (Join-Path $root 'generator-settings.json')) + @(Get-ChildItem -LiteralPath (Join-Path $root 'content\models\zombiesim\signs') -File |
    Where-Object Extension -in '.mdl', '.vvd', '.vtx', '.phy' | Select-Object -ExpandProperty FullName) +
    @(Get-ChildItem -LiteralPath (Join-Path $root 'content\materials\models\zombiesim\signs') -File | Select-Object -ExpandProperty FullName)
$reportPath = Join-Path $output 'compile-report.json'
$needsCompile = -not (Test-Path -LiteralPath $bspPath) -or -not (Test-Path -LiteralPath $reportPath)
if (-not $needsCompile) {
    $previous = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $needsCompile = $previous.status -ne 'passed'
    foreach ($dependency in $dependencies) {
        if ((Get-Item -LiteralPath $dependency).LastWriteTimeUtc -gt (Get-Item -LiteralPath $bspPath).LastWriteTimeUtc) { $needsCompile = $true }
    }
}
if ($needsCompile) {
    Write-Host 'Compiling exactly ONE development BSP: zn_dev_sign_zoo. No city or production maps.'
    [System.IO.File]::WriteAllText($reportPath, '{"status":"incomplete"}', $utf8)
    if (Test-Path -LiteralPath $bspPath) { Remove-Item -LiteralPath $bspPath }
    foreach ($stage in 'vbsp', 'vvis', 'vrad') {
        $tool = Join-Path $compilerDirectory "$stage.exe"
        if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing compiler: $tool" }
        $logPath = Join-Path $output "$name.$stage.log"
        $tokens = if ($stage -eq 'vbsp') { @('-game', '{gameDirectory}', '{mapVmf}') } else { @($profile.Settings.compilation.stagePresets.final.$stage) }
        $arguments = @($tokens | ForEach-Object {
            '"' + $_.Replace('{gameDirectory}', $gameDirectory).Replace('{mapVmf}', $vmfPath).Replace('{mapBsp}', $bspPath) + '"'
        }) -join ' '
        Invoke-SignCompiler $tool $arguments $logPath
        $log = Get-Content -LiteralPath $logPath -Raw
        if ($log -match '(?im)\bleaked!|\*\*\*\s*leaked\b|^\s*Error:|^\s*Error opening|\*\*\*\s*Error') {
            throw "$stage failed; see $logPath"
        }
        if (-not (Test-Path -LiteralPath $bspPath -PathType Leaf)) { throw "$stage produced no BSP; see $logPath" }
        if ($stage -eq 'vbsp') {
            $portalHeader = @(Get-Content -LiteralPath (Join-Path $output "$name.prt") -TotalCount 3)
            if ($portalHeader.Count -ne 3 -or $portalHeader[0] -ne 'PRT1') { throw 'Invalid zoo portal data.' }
            $clusters = [int]$portalHeader[1]; $portals = [int]$portalHeader[2]
            if ($clusters -gt 256 -or $portals -gt 512) { throw "Zoo exceeds focused visibility budget: $clusters clusters, $portals portals." }
        }
        Write-Host "$name $stage passed."
    }
    [pscustomobject]@{ status = 'passed'; map = $name; lightingPreset = 'final'; portalClusters = $clusters; portals = $portals } |
        ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding UTF8
} else { Write-Host 'Zoo BSP is current; no recompilation needed.' }
$maps = Join-Path $gameDirectory 'maps'
$null = New-Item -ItemType Directory -Force -Path $maps
$destination = Join-Path $maps "$name.bsp"
Copy-Item -LiteralPath $bspPath -Destination $destination -Force
if ((Get-FileHash -LiteralPath $bspPath).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw 'Zoo BSP staging hash mismatch.' }
Write-Host "Development-only map staged: $destination"
& (Join-Path $PSScriptRoot 'test_sign_zoo.ps1') -Compiled
if (-not $?) { throw 'Compiled sign zoo regressions failed.' }
