param(
    [string]$ArtworkPath = '',
    [string]$ImagePath = '',
    [string]$BackgroundImagePath = '',
    [Nullable[bool]]$SelfLit = $null,
    [string]$DefinitionPath = '',
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [switch]$StageToGame
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'vpk_reader.psm1') -Force
$projectRoot = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
if ($profile.Name -ne 'preview') { throw 'The sign prototype is preview-only.' }
$gmodRoot = (Resolve-Path (Join-Path $projectRoot '..\..\..')).Path
$output = Join-Path $projectRoot 'generated\signs_preview'
$source = Join-Path $output 'modelsrc'
$game = Join-Path $output 'game'
$materials = Join-Path $game 'materials\models\zombiesim\signs'
$null = New-Item -ItemType Directory -Force -Path $source, $materials
if (-not $DefinitionPath) { $DefinitionPath = Join-Path $projectRoot 'assets\signs\alert_billboard.json' }
$DefinitionPath = (Resolve-Path -LiteralPath $DefinitionPath).Path
$definitionDirectory = Split-Path -Parent $DefinitionPath
$definition = Get-SignArtworkDefinition $DefinitionPath
if (-not $PSBoundParameters.ContainsKey('ImagePath') -and $null -ne $definition.PSObject.Properties['imagePath']) {
    $ImagePath = [string]$definition.imagePath
    if ($ImagePath -and -not [System.IO.Path]::IsPathRooted($ImagePath)) { $ImagePath = Join-Path $definitionDirectory $ImagePath }
}
if (-not $PSBoundParameters.ContainsKey('BackgroundImagePath') -and $null -ne $definition.PSObject.Properties['backgroundImagePath']) {
    $BackgroundImagePath = [string]$definition.backgroundImagePath
    if ($BackgroundImagePath -and -not [System.IO.Path]::IsPathRooted($BackgroundImagePath)) { $BackgroundImagePath = Join-Path $definitionDirectory $BackgroundImagePath }
}
if ($ArtworkPath -and ($ImagePath -or $BackgroundImagePath)) { throw 'Use ArtworkPath for a finished panel, or ImagePath/BackgroundImagePath for layering, not both.' }
$selfLitValue = if ($null -ne $SelfLit) { [bool]$SelfLit } elseif ($null -ne $definition.PSObject.Properties['selfLit']) { $definition.selfLit } else { $false }
$brightness = if ($null -ne $definition.PSObject.Properties['selfIllumBrightness']) { [double]$definition.selfIllumBrightness } else { 0.85 }
$search = New-VpkSearchPath -LooseDirectories @((Join-Path $projectRoot 'content'), (Join-Path $gmodRoot 'garrysmod')) -VpkPaths @(
    (Join-Path $gmodRoot 'garrysmod\garrysmod_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\content_cstrike_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\hl2_textures_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\hl2_misc_dir.vpk')
)
foreach ($component in 'legs', 'rim', 'back') {
    foreach ($key in 'baseTexture', 'normalMap') {
        $texture = [string]$definition.materials.$component.$key
        if ($texture -and $null -eq (Read-VpkSearchPathFile $search "materials/$texture.vtf" -MaxBytes 32)) {
            throw "Required $component texture is missing: $texture"
        }
    }
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'), @'
"GameInfo"
{
    game "ZombieSim sign prototype"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths
        {
            game |gameinfo_path|.
        }
    }
}
'@, $utf8)

if ([string]::IsNullOrWhiteSpace($ArtworkPath)) {
    $ArtworkPath = Join-Path $source 'artwork-template.png'
    [ZombieSim.SignAssets.Builder]::DrawArtwork($ArtworkPath, $definition.width, $definition.height,
        $definition.background, $definition.foreground, $definition.accent, $definition.title, $definition.subtitle, $definition.footer)
    if ($ImagePath -or $BackgroundImagePath) {
        if ($ImagePath) { $ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path }
        if ($BackgroundImagePath) { $BackgroundImagePath = (Resolve-Path -LiteralPath $BackgroundImagePath).Path }
        $composite = Join-Path $source 'artwork-composite.png'
        [ZombieSim.SignAssets.Builder]::ComposeArtwork($composite, $ImagePath, $BackgroundImagePath, $ArtworkPath, $definition.background)
        $ArtworkPath = $composite
    }
} else {
    $ArtworkPath = (Resolve-Path -LiteralPath $ArtworkPath).Path
}
$textureSource = Join-Path $source 'alert_billboard.tga'
[ZombieSim.SignAssets.Builder]::WriteTga($ArtworkPath, $textureSource, 1024, 512)
$lampPng = Join-Path $source 'lamp.png'
$lamp = [System.Drawing.Bitmap]::new(32,32)
$graphics = [System.Drawing.Graphics]::FromImage($lamp)
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(255,238,208))
    $lamp.Save($lampPng, [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $lamp.Dispose() }
[ZombieSim.SignAssets.Builder]::WriteTga($lampPng, (Join-Path $source 'billboard_lamp.tga'), 32, 32)

$vtex = Join-Path $gmodRoot 'bin\vtex.exe'
$studiomdl = Join-Path $gmodRoot 'bin\studiomdl.exe'
foreach ($tool in $vtex, $studiomdl) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Source compiler: $tool" }
}
foreach ($texture in 'alert_billboard', 'billboard_lamp') {
    [System.IO.File]::WriteAllText((Join-Path $source "$texture.txt"), "nolod 1`r`n", $utf8)
    $vtf = Join-Path $materials "$texture.vtf"
    if (Test-Path -LiteralPath $vtf) { Remove-Item -LiteralPath $vtf }
    Invoke-SignCompiler $vtex ('-nop4 -nopause -game "{0}" -outdir "{1}" "{2}"' -f $game, $materials, (Join-Path $source "$texture.tga")) (Join-Path $source "$texture-vtex.log")
    if (-not (Test-Path -LiteralPath $vtf -PathType Leaf)) { throw "vtex produced no texture; see $source\$texture-vtex.log" }
    if ($texture -eq 'alert_billboard') {
        $vmt = Get-SignPanelMaterial $selfLitValue $brightness
    } else {
        $vmt = (Get-SignPanelMaterial $true 1).Replace('models/zombiesim/signs/alert_billboard', 'models/zombiesim/signs/billboard_lamp')
    }
    [System.IO.File]::WriteAllText((Join-Path $materials "$texture.vmt"), $vmt, $utf8)
}
[System.IO.File]::WriteAllText((Join-Path $materials 'alert_billboard_lit.vmt'), (Get-SignPanelMaterial $false $brightness), $utf8)
foreach ($component in 'legs', 'rim', 'back') {
    $texture = [string]$definition.materials.$component.baseTexture
    $normal = [string]$definition.materials.$component.normalMap
    $normalLine = if ($normal) { '    "$bumpmap" "' + $normal + '"' } else { '' }
    [System.IO.File]::WriteAllText((Join-Path $materials "billboard_$component.vmt"), @"
"VertexLitGeneric"
{
    "`$basetexture" "$texture"
$normalLine
    "`$surfaceprop" "metal"
}
"@, $utf8)
}
$variants = [ordered]@{
    freestanding = 'alert_billboard'; panel = 'alert_billboard_panel'; illuminated = 'alert_billboard_illuminated'
    wall = 'alert_billboard_wall'; print = 'alert_billboard_print'; poster = 'alert_billboard_poster'
}
foreach ($variant in $variants.Keys) {
    $name = $variants[$variant]
    [System.IO.File]::WriteAllText((Join-Path $source "$name.smd"), [ZombieSim.SignAssets.Builder]::MeshVariant($false, $variant), $utf8)
    $collisionQc = ''
    if ($variant -ne 'poster') {
        [System.IO.File]::WriteAllText((Join-Path $source "${name}_collision.smd"), [ZombieSim.SignAssets.Builder]::MeshVariant($true, $variant), $utf8)
        $collisionQc = @"
`$collisionmodel "${name}_collision.smd"
{
    `$concave
    `$mass 100
}
"@
    }
    $qc = Join-Path $source "$name.qc"
    [System.IO.File]::WriteAllText($qc, @"
`$modelname "zombiesim/signs/$name.mdl"
`$staticprop
`$surfaceprop "metal"
`$cdmaterials "models/zombiesim/signs/"
`$body body "$name.smd"
`$sequence idle "$name.smd"
$collisionQc
"@, $utf8)
    $compiledBase = Join-Path $game "models\zombiesim\signs\$name"
    foreach ($extension in '.mdl', '.vvd', '.dx90.vtx', '.phy', '.dx80.vtx', '.sw.vtx') {
        if (Test-Path -LiteralPath "$compiledBase$extension") { Remove-Item -LiteralPath "$compiledBase$extension" }
    }
    $modelLog = Join-Path $source "$name-studiomdl.log"
    Invoke-SignCompiler $studiomdl ('-nop4 -game "{0}" "{1}"' -f $game, $qc) $modelLog
    $modelLogText = Get-Content -LiteralPath $modelLog -Raw
    $parts = if ($variant -eq 'freestanding') { 5 } elseif ($variant -eq 'illuminated') { 7 } else { 1 }
    if ($modelLogText -match 'Error with convex|2-dimensional geometry|ERROR:' -or
        ($variant -ne 'poster' -and -not $modelLogText.Contains("Model has $parts convex sub-parts"))) {
        throw "Billboard model/collision compilation was incomplete; see $modelLog"
    }
    $requiredExtensions = if ($variant -eq 'poster') { @('.mdl', '.vvd', '.dx90.vtx') } else { @('.mdl', '.vvd', '.dx90.vtx', '.phy') }
    foreach ($extension in $requiredExtensions) {
        if (-not (Test-Path -LiteralPath "$compiledBase$extension" -PathType Leaf)) { throw "Missing compiled sign output: $compiledBase$extension" }
    }
}

# Mounted metal textures are referenced, never copied into addon content.
$contentMaterials = Join-Path $projectRoot 'content\materials\models\zombiesim\signs'
$contentModels = Join-Path $projectRoot 'content\models\zombiesim\signs'
$null = New-Item -ItemType Directory -Force -Path $contentMaterials, $contentModels
foreach ($file in 'alert_billboard.vtf', 'alert_billboard.vmt', 'alert_billboard_lit.vmt',
    'billboard_legs.vmt', 'billboard_rim.vmt', 'billboard_back.vmt', 'billboard_lamp.vmt', 'billboard_lamp.vtf') {
    Copy-Item -LiteralPath (Join-Path $materials $file) -Destination $contentMaterials -Force
}
foreach ($file in 'billboard_frame.vtf', 'billboard_frame.vmt') {
    $obsoleteFrame = Join-Path $contentMaterials $file
    if (Test-Path -LiteralPath $obsoleteFrame) { Remove-Item -LiteralPath $obsoleteFrame }
}
foreach ($name in $variants.Values) {
    $compiledBase = Join-Path $game "models\zombiesim\signs\$name"
    foreach ($extension in '.mdl', '.vvd', '.dx90.vtx', '.phy', '.dx80.vtx', '.sw.vtx') {
        if (Test-Path -LiteralPath "$compiledBase$extension") {
            Copy-Item -LiteralPath "$compiledBase$extension" -Destination $contentModels -Force
        }
    }
}
$prefabs = Join-Path $output 'prefabs'
$null = New-Item -ItemType Directory -Force -Path $prefabs
$catalog = [ordered]@{}
foreach ($variant in $variants.Keys) {
    $name = $variants[$variant]
    $catalog[$variant] = [ordered]@{
        model = "models/zombiesim/signs/$name.mdl"
        wallMounted = $variant -in @('wall', 'print', 'poster')
        collision = $variant -ne 'poster'
    }
    $solid = if ($variant -eq 'poster') { 0 } else { 6 }
    $lightEntity = ''
    if ($variant -eq 'illuminated') {
        $catalog[$variant].light = [ordered]@{
            origin = @(0, -56, 298); angles = @(60, 90, 0)
            color = '255 238 208 255'; fov = 120; farZ = 256
        }
        $lightEntity = @'
entity
{
    "id" "3"
    "classname" "light_spot"
    "origin" "0 -56 298"
    "angles" "-60 90 0"
    "pitch" "-60"
    "_light" "255 238 208 400"
    "_inner_cone" "55"
    "_cone" "60"
    "_quadratic_attn" "1"
    "_lightHDR" "-1 -1 -1 1"
    "_lightscaleHDR" "1"
}
'@
    }
    $prefab = @"
versioninfo
{
    "editorversion" "400"
    "editorbuild" "0"
    "mapversion" "1"
    "formatversion" "100"
    "prefab" "1"
}
world
{
    "id" "1"
    "classname" "worldspawn"
}
entity
{
    "id" "2"
    "classname" "prop_static"
    "model" "models/zombiesim/signs/$name.mdl"
    "origin" "0 0 0"
    "angles" "0 0 0"
    "skin" "0"
    "solid" "$solid"
}
$lightEntity
"@
    [System.IO.File]::WriteAllText((Join-Path $prefabs "$name.vmf"), $prefab, $utf8)
}
$catalogDirectory = Join-Path $projectRoot 'content\data_static'
$catalogPath = Join-Path $catalogDirectory 'zombiesim_signs_preview.json'
[System.IO.File]::WriteAllText($catalogPath, ([ordered]@{
    schemaVersion = 1; selfLit = $selfLitValue; selfIllumBrightness = $brightness
    materials = $definition.materials; variants = $catalog
} | ConvertTo-Json -Depth 8), $utf8)
Write-Host 'Built six original sign variants: freestanding, panel, illuminated, wall, print and poster.'
Write-Host "Artwork input: $ArtworkPath"
Write-Host "Self-lit panel: $selfLitValue (brightness $brightness); frame uses mounted HL2 metal."
Write-Host 'No city recipes, BSPs, production outputs or skybox manifests were rebuilt.'
if ($StageToGame) {
    & (Join-Path $PSScriptRoot 'stage_sign_assets.ps1')
    if (-not $?) { throw 'Development sign staging failed.' }
}
