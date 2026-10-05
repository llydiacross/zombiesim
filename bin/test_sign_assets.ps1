param([string]$TestImagePath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$output = Join-Path $root 'generated\signs_preview'
$fixtures = Join-Path $output 'tests'
$null = New-Item -ItemType Directory -Force -Path $fixtures
$cases = [System.Collections.Generic.List[object]]::new()
$reportPath = Join-Path $output 'test-report.json'
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
function Assert-Sign([string]$Name, [bool]$Passed) {
    $cases.Add([pscustomobject]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Sign regression failed: $Name" }
    Write-Host "PASS: $Name"
}
$modelBase = Join-Path $root 'content\models\zombiesim\signs\alert_billboard'
$materialRoot = Join-Path $root 'content\materials\models\zombiesim\signs'
$definition = Get-SignArtworkDefinition (Join-Path $root 'assets\signs\alert_billboard.json')
if ($TestImagePath) {
    $definition.imagePath = (Resolve-Path -LiteralPath $TestImagePath).Path
    $definition.backgroundImagePath = ''
    $definition.materials.legs.baseTexture = 'metal/metalwall025a'
    $definition.materials.legs.normalMap = ''
    $definition.materials.rim.baseTexture = 'metal/metalwall021a'
    $definition.materials.rim.normalMap = 'metal/metalwall018a_normal'
    $jsonFixture = Join-Path $fixtures 'artwork.json'
    try {
        $definition | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonFixture -Encoding UTF8
        & (Join-Path $PSScriptRoot 'build_sign_assets.ps1') -WorldProfile preview -DefinitionPath $jsonFixture
        $builtCatalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\zombiesim_signs_preview.json') -Raw | ConvertFrom-Json
        Assert-Sign 'JSON artwork path builds without an image command-line argument' (Test-Path -LiteralPath (Join-Path $output 'modelsrc\artwork-composite.png'))
        Assert-Sign 'JSON leg and rim texture overrides survive the whole build' (
            $builtCatalog.materials.legs.baseTexture -eq 'metal/metalwall025a' -and
            $builtCatalog.materials.rim.baseTexture -eq 'metal/metalwall021a')
    } finally {
        if (Test-Path -LiteralPath $jsonFixture) { Remove-Item -LiteralPath $jsonFixture }
    }
}
Assert-Sign 'editable artwork uses a 2:1 1024x512 canvas' ($definition.width -eq 1024 -and $definition.height -eq 512)
foreach ($extension in '.mdl', '.vvd', '.dx90.vtx', '.phy') {
    Assert-Sign "compiled model has $extension" (Test-Path -LiteralPath "$modelBase$extension" -PathType Leaf)
}
$header = [System.IO.File]::ReadAllBytes("$modelBase.mdl")
Assert-Sign 'compiled model has Source IDST header' ([System.Text.Encoding]::ASCII.GetString($header, 0, 4) -eq 'IDST')
$expected = @(-136.25, -14.8, -0.25, 136.25, 24, 296.25)
for ($axis = 0; $axis -lt 6; $axis++) {
    $actual = [System.BitConverter]::ToSingle($header, 104 + 4 * $axis)
    Assert-Sign "compiled model keeps authored axis/bound $axis" ([math]::Abs($actual - $expected[$axis]) -lt 0.02)
}
foreach ($texture in 'alert_billboard') {
    $vtf = [System.IO.File]::ReadAllBytes((Join-Path $materialRoot "$texture.vtf"))
    $width = if ($texture -eq 'alert_billboard') { 1024 } else { 32 }
    $height = if ($texture -eq 'alert_billboard') { 512 } else { 32 }
    Assert-Sign "$texture has a valid VTF header and dimensions" (
        [System.Text.Encoding]::ASCII.GetString($vtf, 0, 3) -eq 'VTF' -and
        [System.BitConverter]::ToUInt16($vtf, 16) -eq $width -and
        [System.BitConverter]::ToUInt16($vtf, 18) -eq $height)
    $vmt = Get-Content -LiteralPath (Join-Path $materialRoot "$texture.vmt") -Raw
    Assert-Sign "$texture uses its own lit addon texture" ($vmt.Contains('"VertexLitGeneric"') -and $vmt.Contains("models/zombiesim/signs/$texture"))
}
$frameVmt = Get-Content -LiteralPath (Join-Path $materialRoot 'billboard_legs.vmt') -Raw
$catalog = Get-Content -LiteralPath (Join-Path $root 'content\data_static\zombiesim_signs_preview.json') -Raw | ConvertFrom-Json
foreach ($component in 'legs', 'rim', 'back') {
    $componentVmt = Get-Content -LiteralPath (Join-Path $materialRoot "billboard_$component.vmt") -Raw
    $settings = $catalog.materials.$component
    Assert-Sign "$component references its independently configured texture" (
        $componentVmt.Contains(('"$basetexture" "{0}"' -f $settings.baseTexture)))
    Assert-Sign "$component normal map matches its configuration" (
        (-not $settings.normalMap -and $componentVmt -notmatch '\$bumpmap') -or
        $componentVmt.Contains(('"$bumpmap" "{0}"' -f $settings.normalMap)))
    Assert-Sign "$component does not copy a mounted VTF into the addon" (-not (Test-Path -LiteralPath (Join-Path $materialRoot "billboard_$component.vtf")))
}
Assert-Sign 'self-lit panel variant is bounded and uses selfillum, not an unlit frame' (
    (Get-SignPanelMaterial $true 0.85).Contains('"$selfillum" "1"') -and
    (Get-SignPanelMaterial $true 0.85).Contains('"$selfillumtint" "[0.85 0.85 0.85]"') -and
    $frameVmt -notmatch '\$selfillum')
Assert-Sign 'ordinary lit panel remains selectable' ((Get-SignPanelMaterial $false 0.85).Contains('"$selfillum" "0"'))
$log = Get-Content -LiteralPath (Join-Path $output 'modelsrc\alert_billboard-studiomdl.log') -Raw
Assert-Sign 'collision keeps panel, posts and foot plates separate without fallback' (
    $log.Contains('Model has 5 convex sub-parts') -and $log -notmatch 'Error with convex|2-dimensional geometry|ERROR:')
$variantBounds = @{
    panel = @(-136.25, -11.8, -0.25, 136.25, 24, 144.25)
    illuminated = @(-136.25, -62.25, -0.25, 136.25, 24, 306.25)
    wall = @(-52.25, -8.3, -28.25, 52.25, 0.25, 28.25)
    print = @(-136.25, -2.3, -72.25, 136.25, 0.25, 72.25)
    poster = @(-128, -0.1, -64, 128, 0, 64)
}
foreach ($variant in 'panel', 'illuminated', 'wall', 'print', 'poster') {
    $name = "alert_billboard_$variant"
    $base = Join-Path $root "content\models\zombiesim\signs\$name"
    $requiredExtensions = if ($variant -eq 'poster') { @('.mdl', '.vvd', '.dx90.vtx') } else { @('.mdl', '.vvd', '.dx90.vtx', '.phy') }
    foreach ($extension in $requiredExtensions) {
        Assert-Sign "$variant package contains $extension" (Test-Path -LiteralPath "$base$extension")
    }
    $bytes = [System.IO.File]::ReadAllBytes("$base.mdl")
    for ($axis = 0; $axis -lt 6; $axis++) {
        Assert-Sign "$variant compiled bound $axis matches its mounting convention" (
            [math]::Abs([System.BitConverter]::ToSingle($bytes, 104 + 4 * $axis) - $variantBounds[$variant][$axis]) -lt 0.02)
    }
    $expectedParts = if ($variant -eq 'illuminated') { 7 } else { 1 }
    $variantLog = Get-Content -LiteralPath (Join-Path $output "modelsrc\$name-studiomdl.log") -Raw
    if ($variant -eq 'poster') {
        Assert-Sign 'paper-thin poster has no physics hull or collision compiler fallback' (
            -not (Test-Path -LiteralPath "$base.phy") -and $variantLog -notmatch 'convex sub-parts|2-dimensional geometry|ERROR:')
    } else {
        Assert-Sign "$variant collision has the correct parts without fallback" (
            $variantLog.Contains("Model has $expectedParts convex sub-parts") -and $variantLog -notmatch 'Error with convex|2-dimensional geometry|ERROR:')
    }
    $prefab = Get-Content -LiteralPath (Join-Path $output "prefabs\$name.vmf") -Raw
    Assert-Sign "$variant has a reusable static-prop prefab" ($prefab.Contains('"classname" "prop_static"') -and $prefab.Contains("$name.mdl"))
    Assert-Sign "$variant prefab light matches its variant" (($prefab.Contains('"classname" "light_spot"')) -eq ($variant -eq 'illuminated'))
    if ($variant -eq 'illuminated') {
        Assert-Sign 'baked spotlight uses VRAD negative-down pitch, not the runtime Angle convention' (
            $prefab.Contains('"pitch" "-60"') -and $prefab.Contains('"angles" "-60 90 0"'))
    }
    Assert-Sign "$variant is selectable through the generated runtime catalog" ($catalog.variants.$variant.model -eq "models/zombiesim/signs/$name.mdl")
    Assert-Sign "$variant mounting metadata matches the physical asset" (
        $catalog.variants.$variant.wallMounted -eq ($variant -in @('wall', 'print', 'poster')) -and
        $catalog.variants.$variant.collision -eq ($variant -ne 'poster') -and
        $prefab.Contains(('"solid" "{0}"' -f $(if ($variant -eq 'poster') { 0 } else { 6 }))))
}
$lampVmt = Get-Content -LiteralPath (Join-Path $materialRoot 'billboard_lamp.vmt') -Raw
$litPanelVmt = Get-Content -LiteralPath (Join-Path $materialRoot 'alert_billboard_lit.vmt') -Raw
Assert-Sign 'physical lamp has a glowing lens and an ordinary lit panel' (
    $lampVmt.Contains('"$selfillum" "1"') -and $litPanelVmt.Contains('"$selfillum" "0"'))
Assert-Sign 'lamp preview metadata aims from the fixture onto the panel, with bounded light range' (
    $catalog.variants.illuminated.light.origin[1] -eq -56 -and
    $catalog.variants.illuminated.light.origin[2] -eq 298 -and
    $catalog.variants.illuminated.light.angles[0] -eq 60 -and
    $catalog.variants.illuminated.light.angles[1] -eq 90 -and
    $catalog.variants.illuminated.light.farZ -eq 256)

$mesh = [ZombieSim.SignAssets.Builder]::Mesh($false)
$meshMetrics = [System.Collections.Generic.List[object]]::new()
foreach ($variant in 'freestanding', 'panel', 'illuminated', 'wall', 'print', 'poster') {
    $variantMesh = [ZombieSim.SignAssets.Builder]::MeshVariant($false, $variant)
    $triangles = ([regex]::Matches($variantMesh, '(?m)^(?:billboard_[a-z]+|alert_billboard(?:_lit)?)\r?$')).Count
    $meshMetrics.Add([pscustomobject]@{ variant = $variant; triangles = $triangles })
    Assert-Sign "$variant geometry stays below 1000 triangles" ($triangles -gt 0 -and $triangles -lt 1000)
    if ($variant -eq 'poster') {
        Assert-Sign 'borderless poster is exactly two image triangles without rim, backing or legs' (
            $triangles -eq 2 -and $variantMesh -notmatch 'billboard_rim|billboard_back|billboard_legs')
    }
    if ($variant -in @('freestanding', 'panel', 'illuminated')) {
        $slopeVertices = @($variantMesh -split '\r?\n' | Where-Object {
            $parts = $_ -split ' '
            $parts.Count -eq 9 -and $parts[0] -eq '0' -and
                [math]::Abs([double]$parts[4]) -gt 0.1 -and [math]::Abs([double]$parts[4]) -lt 0.95 -and
                ([math]::Abs([double]$parts[5]) -gt 0.1 -or [math]::Abs([double]$parts[6]) -gt 0.1)
        })
        Assert-Sign "$variant has actual bevel slope normals, not a flat painted border" (
            $slopeVertices.Count -ge 24 -and $variantMesh -match '0 -11 ' -and $triangles -gt 150)
    }
}
$meshMetrics | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'mesh-budget.json') -Encoding UTF8
$lines = $mesh -split '\r?\n'
$panelIndex = [array]::IndexOf($lines, 'alert_billboard')
$vertices = @($lines[($panelIndex + 1)..($panelIndex + 3)] | ForEach-Object { ,($_ -split ' ') })
# Inverse of the documented studiomdl axis conversion: model X=-SMD Y, model Y=SMD X.
Assert-Sign 'artwork lower-left is UV 0,0 on the south face' (
    [double]$vertices[0][2] -eq 128 -and [double]$vertices[0][1] -eq -8.1 -and
    [double]$vertices[0][3] -eq 160 -and [double]$vertices[0][7] -eq 0 -and [double]$vertices[0][8] -eq 0)
Assert-Sign 'artwork lower-right and upper-right UVs are upright, not mirrored' (
    [double]$vertices[1][2] -eq -128 -and [double]$vertices[1][7] -eq 1 -and [double]$vertices[1][8] -eq 0 -and
    [double]$vertices[2][3] -eq 288 -and [double]$vertices[2][7] -eq 1 -and [double]$vertices[2][8] -eq 1)

$badImage = Join-Path $fixtures 'invalid.png'
$badTga = Join-Path $fixtures 'invalid.tga'
$tile = Join-Path $fixtures 'billboard_tile.vmf'
$recipe = Join-Path $fixtures 'billboard_recipe.vmf'
$backgroundImage = Join-Path $fixtures 'background.png'
$foregroundImage = Join-Path $fixtures 'foreground.png'
$compositeImage = Join-Path $fixtures 'composite.png'
try {
    $background = [System.Drawing.Bitmap]::new(64, 64)
    $graphics = [System.Drawing.Graphics]::FromImage($background)
    try {
        $graphics.Clear([System.Drawing.Color]::Blue)
        $background.Save($backgroundImage, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $background.Dispose() }
    $foreground = [System.Drawing.Bitmap]::new(64, 64)
    $graphics = [System.Drawing.Graphics]::FromImage($foreground)
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Red)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillRectangle($brush, 16, 16, 32, 32)
        $foreground.Save($foregroundImage, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $brush.Dispose(); $graphics.Dispose(); $foreground.Dispose() }
    [ZombieSim.SignAssets.Builder]::ComposeArtwork($compositeImage, $foregroundImage, $backgroundImage, '', '#173438')
    $composite = [System.Drawing.Bitmap]::new($compositeImage)
    try {
        Assert-Sign 'background cover fills all edges, including non-2:1 sources' ($composite.GetPixel(0, 0).B -gt 240 -and $composite.GetPixel(1023, 511).B -gt 240)
        Assert-Sign 'transparent foreground is centered over the background' ($composite.GetPixel(512, 256).R -gt 240 -and $composite.GetPixel(320, 64).B -gt 240)
        Assert-Sign 'foreground contain preserves square aspect ratio' ($composite.GetPixel(410, 256).R -gt 240 -and $composite.GetPixel(512, 154).R -gt 240 -and
            $composite.GetPixel(380, 256).B -gt 240 -and $composite.GetPixel(512, 124).B -gt 240)
    } finally { $composite.Dispose() }
    [ZombieSim.SignAssets.Builder]::WriteTga($compositeImage, (Join-Path $fixtures 'invalid.tga'), 1024, 512)
    Assert-Sign 'transparent layers flatten to an opaque compiler-ready panel' (Test-Path -LiteralPath $badTga)
    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    try { $bitmap.Save($badImage, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    $rejected = $false
    try { [ZombieSim.SignAssets.Builder]::WriteTga($badImage, $badTga, 1024, 512) }
    catch {
        if ($_.Exception.ToString() -notmatch 'Artwork must be exactly') { throw }
        $rejected = $true
    }
    Assert-Sign 'wrong-size artwork is rejected rather than stretched' $rejected
    $bitmap = [System.Drawing.Bitmap]::new(1024, 512)
    try { $bitmap.Save($badImage, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    $rejected = $false
    try { [ZombieSim.SignAssets.Builder]::WriteTga($badImage, $badTga, 1024, 512) }
    catch {
        if ($_.Exception.ToString() -notmatch 'artwork must be opaque') { throw }
        $rejected = $true
    }
    Assert-Sign 'transparent artwork is rejected explicitly' $rejected
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $tileTemplate = @'
entity
{
    "classname" "prop_static"
    "model" "models/zombiesim/signs/{0}.mdl"
    "origin" "32 0 0"
    "angles" "0 0 0"
    "skin" "0"
}
'@
    $instances = for ($i = 0; $i -lt 4; $i++) {
        @"
entity
{
    "classname" "func_instance"
    "file" "billboard_tile.vmf"
    "origin" "$($i * 640) 0 0"
    "angles" "0 $($i * 90) 0"
}
"@
    }
    [System.IO.File]::WriteAllText($recipe, ($instances -join "`r`n"), $utf8)
    $settings = $profile.Settings.vmfBuild.skybox3d
    $pattern = if ($settings.ContainsKey('detailPropPattern')) { [string]$settings.detailPropPattern } else { 'billboard' }
    $dx = @(32, 0, -32, 0); $dy = @(0, 32, 0, -32)
    foreach ($name in 'alert_billboard', 'alert_billboard_panel', 'alert_billboard_illuminated', 'alert_billboard_wall', 'alert_billboard_print', 'alert_billboard_poster') {
        [System.IO.File]::WriteAllText($tile, $tileTemplate.Replace('{0}', $name), $utf8)
        $builder = [ZombieSim.Skybox.CellModelBuilder]::new(24)
        $details = $builder.BuildDetail($recipe, $pattern, '^$', 'concrete/concretefloor037a', [string[]]@(), 320, 0, 192)
        Assert-Sign "skybox path retains all four $name instances" ($details.Props.Count -eq 4)
        for ($i = 0; $i -lt 4; $i++) {
            $prop = $details.Props[$i]
            $yawDelta = (($prop.Angles.Y - $i * 90 + 540) % 360) - 180
            Assert-Sign "$name yaw $($i * 90) preserves model, artwork skin, position and facing" (
                $prop.Model -eq "models/zombiesim/signs/$name.mdl" -and $prop.Skin -eq 0 -and
                [math]::Abs($prop.Origin.X - ($i * 640 + $dx[$i])) -lt 0.001 -and
                [math]::Abs($prop.Origin.Y - $dy[$i]) -lt 0.001 -and
                [math]::Abs($yawDelta) -lt 0.001)
        }
    }
} finally {
    foreach ($path in $badImage, $badTga, $tile, $recipe, $backgroundImage, $foregroundImage, $compositeImage) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    [pscustomobject]@{ cases = $cases.ToArray(); passed = @($cases | Where-Object passed).Count } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'test-report.json') -Encoding UTF8
}
Write-Host "Sign asset regressions passed: $($cases.Count)/$($cases.Count)."
