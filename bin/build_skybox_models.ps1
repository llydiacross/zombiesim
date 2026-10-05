param(
    [string]$PlanData = '',
    [string]$OutputContentDirectory = '',
    [switch]$Force,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = ''
)

# Builds the runtime 3D skybox content for a world profile: every unique cell recipe in the template plan is converted
# from its tile instances into scaled static models, and a manifest maps recipe names to those models. Every city recipe
# carries the same sky_camera room (written by build_cell_vmfs.ps1); gamemode/cl_skybox.lua draws the current cell's
# neighbours inside it from this manifest, so recipes shared by many cells still show the correct surroundings.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'vpk_reader.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force

# Kept from the prototype builder so its unchanged models are reused rather than recompiled.
$builderVersion = 'skybox-cell-v2'
# Snow overlays carry their own stamps so changing them never recompiles the base cell models.
$snowBuilderVersion = 'skybox-snow-v1'
$towerBuilderVersion = 'skybox-towers-v1'
$manifestSchemaVersion = 1
$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config
$profileName = [string]$profileSettings.filePrefix

$skySettings = @{}
if ($worldGenerationProfile.Settings.vmfBuild.ContainsKey('skybox3d')) { $skySettings = $worldGenerationProfile.Settings.vmfBuild.skybox3d }
function Get-SkySetting([string]$Name, $Fallback) {
    if ($skySettings.ContainsKey($Name)) { return $skySettings[$Name] }
    return $Fallback
}
if (-not [bool](Get-SkySetting 'enabled' $false)) { throw 'vmfBuild.skybox3d.enabled is false; enable it before building skybox models.' }
$skyScale = [int](Get-SkySetting 'scale' 16)
$neighbourRadius = [int](Get-SkySetting 'neighbourRadius' 2)
$skylineRadius = [int](Get-SkySetting 'skylineRadius' $neighbourRadius)
$maxTowerModels = [int](Get-SkySetting 'maxTowerModels' 128)
$cameraZ = [int](Get-SkySetting 'cameraZ' 3328)
$minBrushExtent = [double](Get-SkySetting 'minBrushExtent' 24)
$maxPartVertices = [int](Get-SkySetting 'maxPartVertices' 30000)
# studiomdl rejects models that reference more than 64 materials.
$maxPartMaterials = [math]::Min(60, [int](Get-SkySetting 'maxPartMaterials' 60))
$snowEnabled = [bool](Get-SkySetting 'snowOverlay' $true)
$snowMinNormalZ = [double](Get-SkySetting 'snowMinNormalZ' 0.7)
$snowLift = [double](Get-SkySetting 'snowLift' 8)
$snowTextureWorldSize = [double](Get-SkySetting 'snowTextureWorldSize' 256)
$snowSourceMaterial = 'nature/snowfloor001a'
# Set dressing: authored tile props that read at skybox distance, extra road wrecks, and fire candidates.
$detailEnabled = [bool](Get-SkySetting 'detailProps' $true)
$detailPropPattern = [string](Get-SkySetting 'detailPropPattern' '(/|_)trees?[_0-9]|hedge|lamppost|cargo_container|dumpster|billboard|gaspump|concrete_barrier|concrete_pipe|tracksign|acunit|rocks_medium|vendingmachine')
$detailVehiclePattern = [string](Get-SkySetting 'detailVehiclePattern' 'props_vehicles/(car\d|truck|van|bus|apc|generatortrailer)|/truck\.mdl$')
$roadCarMaterial = [string](Get-SkySetting 'roadCarMaterial' 'CONCRETE/CONCRETEFLOOR037A')
$roadCarModels = @(Get-SkySetting 'roadCarModels' @('models/props_vehicles/car002b_physics.mdl', 'models/props_vehicles/car003a_physics.mdl', 'models/props_vehicles/car005a_physics.mdl', 'models/props_vehicles/car001b_phy.mdl') | ForEach-Object { ([string]$_).ToLowerInvariant() })
$roadCarSpacing = [double](Get-SkySetting 'roadCarSpacing' 320)
$roadCarChance = [double](Get-SkySetting 'roadCarChance' 0.35)
$roofFireMinHeight = [double](Get-SkySetting 'roofFireMinHeight' 192)
$tileSize = [int]$worldGenerationProfile.Settings.vmfBuild.tileSize
if ($skyScale -lt 1 -or $neighbourRadius -lt 1) { throw 'skybox3d scale and neighbourRadius must be positive.' }
if ($skylineRadius -lt $neighbourRadius) { throw 'skybox3d skylineRadius must be at least neighbourRadius.' }
if ($maxTowerModels -lt 1) { throw 'skybox3d maxTowerModels must be positive.' }

$cellDirectory = [string]$profileSettings.cellDirectory
if (-not [System.IO.Path]::IsPathRooted($cellDirectory)) { $cellDirectory = Join-Path $projectRoot $cellDirectory }
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $PlanData = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "$($profileName)_grid_*_template_plan.json" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0].FullName
}
$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$tileGridSize = [int]$plan.cellTileGridSize
# Interior tiles plus the one-tile border ring on each side.
$cellSpan = ($tileGridSize + 2) * $tileSize

$recipePaths = [System.Collections.Generic.List[string]]::new()
foreach ($recipe in @($plan.cells | ForEach-Object { [string]$_.cellTemplateFilename } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
    $recipePath = Join-Path $cellDirectory $recipe
    if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
        throw "Recipe $recipe is missing; run build_cell_vmfs.ps1 for the $profileName profile first."
    }
    $recipePaths.Add($recipePath)
}
if ($recipePaths.Count -eq 0) { throw "The $profileName template plan contains no cell recipes." }
Write-Host "Building skybox models for $($recipePaths.Count) $profileName recipe(s)."
$gmodRoot = (Resolve-Path (Join-Path $projectRoot '..\..\..')).Path
$garrysmodDirectory = Join-Path $gmodRoot 'garrysmod'
$contentDirectory = Join-Path $projectRoot 'content'
$searchPath = New-VpkSearchPath -LooseDirectories @($contentDirectory, $garrysmodDirectory) -VpkPaths @(
    (Join-Path $garrysmodDirectory 'garrysmod_dir.vpk'),
    (Join-Path $garrysmodDirectory 'fallbacks_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\content_cstrike_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\hl2_textures_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\hl2_misc_dir.vpk'),
    (Join-Path $gmodRoot 'sourceengine\content_hl2_dir.vpk')
)

function Get-KeyValue($Node, [string]$Name) {
    foreach ($pair in $Node.Keys) { if ($pair.Key -ieq $Name) { return [string]$pair.Value } }
    return $null
}

function Resolve-VmtDefinition([string]$MaterialPath, [int]$Depth = 0) {
    if ($Depth -gt 4) { return $null }
    $file = Read-VpkSearchPathFile -SearchPath $searchPath -VirtualPath "materials/$MaterialPath.vmt"
    if ($null -eq $file) { return $null }
    $root = [ZombieSim.Skybox.KeyValuesParser]::Parse([System.Text.Encoding]::UTF8.GetString($file.Bytes))
    if ($root.Children.Count -eq 0) { return $null }
    $shaderNode = $root.Children[0]
    if ($shaderNode.Name -ieq 'patch') {
        $include = Get-KeyValue $shaderNode 'include'
        $baseDefinition = $null
        if ($include) { $baseDefinition = Resolve-VmtDefinition (($include -replace '\\', '/') -replace '^materials/', '' -replace '\.vmt$', '') ($Depth + 1) }
        if ($null -eq $baseDefinition) { return $null }
        foreach ($blockName in 'insert', 'replace') {
            $block = $shaderNode.Child($blockName)
            if ($null -eq $block) { continue }
            foreach ($pair in $block.Keys) { $baseDefinition.Values[$pair.Key.ToLowerInvariant()] = [string]$pair.Value }
        }
        return $baseDefinition
    }
    $values = @{}
    foreach ($pair in $shaderNode.Keys) { $values[$pair.Key.ToLowerInvariant()] = [string]$pair.Value }
    return [pscustomobject]@{ Shader = $shaderNode.Name.ToLowerInvariant(); Values = $values; Source = $file.Source }
}

function Get-VtfSize([string]$TexturePath) {
    $file = Read-VpkSearchPathFile -SearchPath $searchPath -VirtualPath "materials/$TexturePath.vtf" -MaxBytes 32
    if ($null -eq $file -or $file.Bytes.Length -lt 20) { return $null }
    return @([System.BitConverter]::ToUInt16($file.Bytes, 16), [System.BitConverter]::ToUInt16($file.Bytes, 18))
}

$outputRoot = Join-Path $projectRoot "generated\skybox_$profileName"
if (-not [string]::IsNullOrWhiteSpace($OutputContentDirectory)) {
    $contentDirectory = if ([System.IO.Path]::IsPathRooted($OutputContentDirectory)) {
        $OutputContentDirectory
    } else {
        Join-Path $projectRoot $OutputContentDirectory
    }
}
$modelSourceDirectory = Join-Path $outputRoot 'modelsrc'
$compileGameDirectory = Join-Path $outputRoot 'game'
$null = New-Item -ItemType Directory -Force -Path $modelSourceDirectory, $compileGameDirectory
$modelRelativeDirectory = 'zombiesim/skybox/cells'
$materialRelativeDirectory = 'models/zombiesim/skybox'
$contentModelDirectory = Join-Path $contentDirectory ('models\' + $modelRelativeDirectory.Replace('/', '\'))
$contentMaterialDirectory = Join-Path $contentDirectory ('materials\' + $materialRelativeDirectory.Replace('/', '\'))
$null = New-Item -ItemType Directory -Force -Path $contentModelDirectory, $contentMaterialDirectory

$builder = [ZombieSim.Skybox.CellModelBuilder]::new($minBrushExtent)
$uniqueRecipes = @($recipePaths)
$materialNames = $builder.CollectMaterials([string[]]$uniqueRecipes)

$materialMap = [System.Collections.Generic.Dictionary[string, ZombieSim.Skybox.MaterialInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
$materialReport = [System.Collections.Generic.List[object]]::new()
foreach ($materialName in $materialNames) {
    $lower = $materialName.ToLowerInvariant().Replace('\', '/')
    if ($lower.StartsWith('tools/')) { $materialReport.Add([pscustomobject]@{ material = $lower; status = 'skipped-tool' }); continue }
    $definition = Resolve-VmtDefinition $lower
    if ($null -eq $definition) { $materialReport.Add([pscustomobject]@{ material = $lower; status = 'missing-vmt' }); continue }
    if ($definition.Shader -match 'water|refract|^sky') { $materialReport.Add([pscustomobject]@{ material = $lower; status = "skipped-$($definition.Shader)" }); continue }
    $baseTexture = $definition.Values['$basetexture']
    if ([string]::IsNullOrWhiteSpace($baseTexture)) { $materialReport.Add([pscustomobject]@{ material = $lower; status = 'no-basetexture' }); continue }
    $baseTexture = ($baseTexture -replace '\\', '/').ToLowerInvariant()
    $size = Get-VtfSize $baseTexture
    if ($null -eq $size) { $size = @(512, 512) }
    $modelMaterial = 'zmsky_' + ($lower -replace '[^a-z0-9]+', '_')
    $vmtLines = [System.Collections.Generic.List[string]]::new()
    $vmtLines.Add('"VertexLitGeneric"')
    $vmtLines.Add('{')
    $vmtLines.Add(('    "$basetexture" "{0}"' -f $baseTexture))
    foreach ($flag in '$alphatest', '$translucent', '$nocull', '$alphatestreference') {
        if ($definition.Values.ContainsKey($flag)) { $vmtLines.Add(('    "{0}" "{1}"' -f $flag, $definition.Values[$flag])) }
    }
    $vmtLines.Add('}')
    $vmtPath = Join-Path $contentMaterialDirectory "$modelMaterial.vmt"
    $vmtText = ($vmtLines -join "`r`n") + "`r`n"
    if (-not (Test-Path -LiteralPath $vmtPath) -or (Get-Content -Raw -LiteralPath $vmtPath) -ne $vmtText) {
        [System.IO.File]::WriteAllText($vmtPath, $vmtText, [System.Text.UTF8Encoding]::new($false))
    }
    $info = [ZombieSim.Skybox.MaterialInfo]::new()
    $info.ModelMaterial = $modelMaterial
    $info.Width = [int]$size[0]
    $info.Height = [int]$size[1]
    $materialMap[$materialName] = $info
    $materialReport.Add([pscustomobject]@{ material = $lower; status = 'ok'; baseTexture = $baseTexture; width = $info.Width; height = $info.Height; vmt = $definition.Source })
}

$studiomdl = Join-Path $gmodRoot 'bin\studiomdl.exe'
if (-not (Test-Path -LiteralPath $studiomdl -PathType Leaf)) { throw "studiomdl.exe was not found at $studiomdl" }
$gameInfoPath = Join-Path $compileGameDirectory 'gameinfo.txt'
$gameInfoText = @'
"GameInfo"
{
    game "ZombieSim skybox model build"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths
        {
            game |gameinfo_path|.
        }
    }
}
'@
[System.IO.File]::WriteAllText($gameInfoPath, $gameInfoText, [System.Text.UTF8Encoding]::new($false))

function Get-TextHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').Substring(0, 16).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-SkyboxModelCompile([string]$partName, [string]$Smd) {
    $smdPath = Join-Path $modelSourceDirectory "$partName.smd"
    $qcPath = Join-Path $modelSourceDirectory "$partName.qc"
    [System.IO.File]::WriteAllText($smdPath, $Smd, [System.Text.UTF8Encoding]::new($false))
    $qcText = @(
        ('$modelname "{0}/{1}.mdl"' -f $modelRelativeDirectory, $partName),
        '$staticprop',
        '$surfaceprop "default"',
        ('$cdmaterials "{0}/"' -f $materialRelativeDirectory),
        ('$body body "{0}.smd"' -f $partName),
        ('$sequence idle "{0}.smd"' -f $partName)
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($qcPath, $qcText + "`r`n", [System.Text.UTF8Encoding]::new($false))

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $studiomdl
    $process.StartInfo.Arguments = ('-nop4 -game "{0}" "{1}"' -f $compileGameDirectory.TrimEnd('\'), $qcPath)
    $process.StartInfo.WorkingDirectory = Split-Path -Parent $studiomdl
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $logPath = Join-Path $modelSourceDirectory "$partName.log"
    [System.IO.File]::WriteAllText($logPath, $stdout + $stderr)
    $compiledBase = Join-Path $compileGameDirectory ('models\' + $modelRelativeDirectory.Replace('/', '\') + "\$partName")
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath "$compiledBase.mdl")) {
        throw "studiomdl failed for $partName (exit $($process.ExitCode)); see $logPath"
    }
    foreach ($extension in '.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx', '.sw.vtx') {
        $compiledFile = "$compiledBase$extension"
        if (Test-Path -LiteralPath $compiledFile) { Copy-Item -LiteralPath $compiledFile -Destination $contentModelDirectory -Force }
    }
}

$materialSignature = ($materialMap.Keys | Sort-Object | ForEach-Object { "$_=$($materialMap[$_].ModelMaterial):$($materialMap[$_].Width)x$($materialMap[$_].Height)" }) -join ';'
$cellModels = @{}
foreach ($recipePath in $uniqueRecipes) {
    $recipeName = [System.IO.Path]::GetFileNameWithoutExtension($recipePath)
    $sourceParts = [System.Collections.Generic.List[string]]::new()
    $sourceParts.Add($builderVersion); $sourceParts.Add("$skyScale|$minBrushExtent|$maxPartVertices|$maxPartMaterials"); $sourceParts.Add($materialSignature)
    $sourceParts.Add((Get-Content -Raw -LiteralPath $recipePath))
    foreach ($tilePath in @([ZombieSim.Skybox.CellModelBuilder]::ReadInstances($recipePath) | ForEach-Object { $_.File } | Sort-Object -Unique)) {
        if (Test-Path -LiteralPath $tilePath) { $sourceParts.Add((Get-FileHash -LiteralPath $tilePath -Algorithm SHA256).Hash) }
    }
    $sourceHash = Get-TextHash ($sourceParts -join "`n")
    $stampPath = Join-Path $modelSourceDirectory "$recipeName.json"
    if (-not $Force -and (Test-Path -LiteralPath $stampPath)) {
        $stamp = Get-Content -Raw -LiteralPath $stampPath | ConvertFrom-Json
        $allPresent = $stamp.sourceHash -eq $sourceHash -and @($stamp.parts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $contentDirectory "models\$($_.model.Replace('/', '\'))")) }).Count -eq 0
        if ($allPresent) {
            $cellModels[$recipePath] = $stamp
            Write-Host "Skybox model current: $recipeName ($(@($stamp.parts).Count) part(s))"
            continue
        }
    }

    $parts = $builder.BuildParts($recipePath, 1.0 / $skyScale, $materialMap, $maxPartVertices, $maxPartMaterials)
    $partRecords = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $part = $parts[$index]
        $partName = "${recipeName}_p$index"
        Invoke-SkyboxModelCompile $partName $part.Smd
        $partRecords.Add([pscustomobject]@{
            model = "$modelRelativeDirectory/$partName.mdl"
            triangles = $part.Triangles
            vertices = $part.Vertices
            min = @($part.Min.X, $part.Min.Y, $part.Min.Z)
            max = @($part.Max.X, $part.Max.Y, $part.Max.Z)
        })
        Write-Host ("Compiled skybox model {0}: {1} triangles, {2} vertices" -f $partName, $part.Triangles, $part.Vertices)
    }
    # Remove parts left over from an earlier build that split the recipe into more pieces.
    Get-ChildItem -LiteralPath $contentModelDirectory -File | Where-Object {
        $_.Name -match ('^' + [regex]::Escape($recipeName) + '_p(\d+)\.') -and [int]$Matches[1] -ge $parts.Count
    } | Remove-Item -Force
    $stamp = [pscustomobject]@{ recipe = $recipeName; sourceHash = $sourceHash; parts = $partRecords.ToArray() }
    [System.IO.File]::WriteAllText($stampPath, ($stamp | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    $cellModels[$recipePath] = $stamp
}

$snowModels = @{}
$snowModelMaterial = 'zmsky_snow_v1'
if ($snowEnabled) {
    $snowDefinition = Resolve-VmtDefinition $snowSourceMaterial
    if ($null -eq $snowDefinition -or [string]::IsNullOrWhiteSpace($snowDefinition.Values['$basetexture'])) {
        throw "The skybox snow material $snowSourceMaterial could not be resolved from the mounted game content."
    }
    $snowTexture = ($snowDefinition.Values['$basetexture'] -replace '\\', '/').ToLowerInvariant()
    $snowVmtText = (@('"VertexLitGeneric"', '{', ('    "$basetexture" "{0}"' -f $snowTexture), '}') -join "`r`n") + "`r`n"
    $snowVmtPath = Join-Path $contentMaterialDirectory "$snowModelMaterial.vmt"
    if (-not (Test-Path -LiteralPath $snowVmtPath) -or (Get-Content -Raw -LiteralPath $snowVmtPath) -ne $snowVmtText) {
        [System.IO.File]::WriteAllText($snowVmtPath, $snowVmtText, [System.Text.UTF8Encoding]::new($false))
    }
    foreach ($recipePath in $uniqueRecipes) {
        $recipeName = [System.IO.Path]::GetFileNameWithoutExtension($recipePath)
        $snowSourceHash = Get-TextHash (@($snowBuilderVersion, "$snowModelMaterial|$snowTexture|$snowMinNormalZ|$snowLift|$snowTextureWorldSize|$maxPartVertices", $cellModels[$recipePath].sourceHash) -join "`n")
        $snowStampPath = Join-Path $modelSourceDirectory "${recipeName}_snow.json"
        if (-not $Force -and (Test-Path -LiteralPath $snowStampPath)) {
            $snowStamp = Get-Content -Raw -LiteralPath $snowStampPath | ConvertFrom-Json
            $snowPresent = $snowStamp.sourceHash -eq $snowSourceHash -and @($snowStamp.parts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $contentDirectory "models\$($_.model.Replace('/', '\'))")) }).Count -eq 0
            if ($snowPresent) {
                $snowModels[$recipePath] = $snowStamp
                continue
            }
        }
        $snowParts = $builder.BuildSnowParts($recipePath, 1.0 / $skyScale, $materialMap, $maxPartVertices, $snowModelMaterial, $snowMinNormalZ, $snowLift, $snowTextureWorldSize)
        $snowRecords = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $snowParts.Count; $index++) {
            $part = $snowParts[$index]
            $partName = "${recipeName}_s$index"
            Invoke-SkyboxModelCompile $partName $part.Smd
            $snowRecords.Add([pscustomobject]@{
                model = "$modelRelativeDirectory/$partName.mdl"
                triangles = $part.Triangles
                vertices = $part.Vertices
            })
            Write-Host ("Compiled skybox snow model {0}: {1} triangles" -f $partName, $part.Triangles)
        }
        Get-ChildItem -LiteralPath $contentModelDirectory -File | Where-Object {
            $_.Name -match ('^' + [regex]::Escape($recipeName) + '_s(\d+)\.') -and [int]$Matches[1] -ge $snowParts.Count
        } | Remove-Item -Force
        $snowStamp = [pscustomobject]@{ recipe = $recipeName; sourceHash = $snowSourceHash; parts = $snowRecords.ToArray() }
        [System.IO.File]::WriteAllText($snowStampPath, ($snowStamp | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
        $snowModels[$recipePath] = $snowStamp
    }
}

$towerModels = @{}
foreach ($recipePath in $uniqueRecipes) {
    $recipeName = [System.IO.Path]::GetFileNameWithoutExtension($recipePath)
    $towerHash = Get-TextHash (@($towerBuilderVersion, $cellModels[$recipePath].sourceHash) -join "`n")
    $towerStampPath = Join-Path $modelSourceDirectory "${recipeName}_towers.json"
    if (-not $Force -and (Test-Path -LiteralPath $towerStampPath)) {
        $towerStamp = Get-Content -Raw -LiteralPath $towerStampPath | ConvertFrom-Json
        $towerPresent = $towerStamp.sourceHash -eq $towerHash -and @($towerStamp.parts | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $contentDirectory "models\$($_.model.Replace('/', '\'))"))
        }).Count -eq 0
        if ($towerPresent) { $towerModels[$recipePath] = $towerStamp; continue }
    }
    $towerParts = $builder.BuildTowerParts($recipePath, 1.0 / $skyScale, $materialMap, $maxPartVertices, $maxPartMaterials)
    $towerRecords = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $towerParts.Count; $index++) {
        $part = $towerParts[$index]
        $partName = "${recipeName}_t$index"
        Invoke-SkyboxModelCompile $partName $part.Smd
        $towerRecords.Add([pscustomobject]@{
            model = "$modelRelativeDirectory/$partName.mdl"
            triangles = $part.Triangles
            vertices = $part.Vertices
            min = @($part.Min.X, $part.Min.Y, $part.Min.Z)
            max = @($part.Max.X, $part.Max.Y, $part.Max.Z)
        })
    }
    Get-ChildItem -LiteralPath $contentModelDirectory -File | Where-Object {
        $_.Name -match ('^' + [regex]::Escape($recipeName) + '_t(\d+)\.') -and [int]$Matches[1] -ge $towerParts.Count
    } | Remove-Item -Force
    $towerStamp = [pscustomobject]@{ recipe = $recipeName; sourceHash = $towerHash; parts = $towerRecords.ToArray() }
    [System.IO.File]::WriteAllText($towerStampPath, ($towerStamp | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    $towerModels[$recipePath] = $towerStamp
}

# Drop models for recipes the current plan no longer uses.
$currentRecipeNames = @{}
foreach ($recipePath in $recipePaths) { $currentRecipeNames[[System.IO.Path]::GetFileNameWithoutExtension($recipePath).ToLowerInvariant()] = $true }
# Model files are shared by every profile, so only recipes with this profile's name prefix are pruned.
$recipePrefixes = @{}
foreach ($name in $currentRecipeNames.Keys) { if ($name -match '^(.*_)[0-9a-f]+$') { $recipePrefixes[$Matches[1]] = $true } }
$prunedModels = 0
foreach ($stale in @(Get-ChildItem -LiteralPath $contentModelDirectory -File | Where-Object {
        $_.Name -match '^((.*_)[0-9a-f]+)_[pst]\d+\.' -and $recipePrefixes.ContainsKey($Matches[2].ToLowerInvariant()) -and -not $currentRecipeNames.ContainsKey($Matches[1].ToLowerInvariant()) })) {
    Remove-Item -LiteralPath $stale.FullName -Force
    $prunedModels++
}

$recipeModels = [ordered]@{}
$totalParts = 0
$totalTriangles = 0
foreach ($recipePath in $recipePaths) {
    $stamp = $cellModels[$recipePath]
    $recipeModels[[System.IO.Path]::GetFileNameWithoutExtension($recipePath).ToLowerInvariant()] = @(@($stamp.parts) | ForEach-Object {
        $totalTriangles += [int]$_.triangles
        "models/$($_.model)"
    })
    $totalParts += @($stamp.parts).Count
}
$recipeSnowModels = [ordered]@{}
$totalSnowParts = 0
$totalSnowTriangles = 0
foreach ($recipePath in $recipePaths) {
    if (-not $snowModels.ContainsKey($recipePath)) { continue }
    $snowStamp = $snowModels[$recipePath]
    $recipeSnowModels[[System.IO.Path]::GetFileNameWithoutExtension($recipePath).ToLowerInvariant()] = @(@($snowStamp.parts) | ForEach-Object {
        $totalSnowTriangles += [int]$_.triangles
        "models/$($_.model)"
    })
    $totalSnowParts += @($snowStamp.parts).Count
}
$detailModels = [System.Collections.Generic.List[string]]::new()
$recipeTowerModels = [ordered]@{}
$totalTowerParts = 0
$totalTowerTriangles = 0
foreach ($recipePath in $recipePaths) {
    $towerStamp = $towerModels[$recipePath]
    $recipeTowerModels[[System.IO.Path]::GetFileNameWithoutExtension($recipePath).ToLowerInvariant()] = @(@($towerStamp.parts) | ForEach-Object {
        $totalTowerTriangles += [int]$_.triangles
        "models/$($_.model)"
    })
    $totalTowerParts += @($towerStamp.parts).Count
}
$detailModelIndex = @{}
$detailRecipes = [ordered]@{}
$missingDetailModels = @{}
$mountedModelCache = @{}
$totalDetailProps = 0
$totalGeneratedCars = 0
$totalFireCandidates = 0
function Format-SkyNumber([double]$Value) { return [math]::Round($Value, 1) }
if ($detailEnabled) {
    foreach ($recipePath in $recipePaths) {
        $detail = $builder.BuildDetail($recipePath, $detailPropPattern, $detailVehiclePattern, $roadCarMaterial, [string[]]$roadCarModels, $roadCarSpacing, $roadCarChance, $roofFireMinHeight)
        $props = [System.Collections.Generic.List[object]]::new()
        foreach ($prop in $detail.Props) {
            if (-not $mountedModelCache.ContainsKey($prop.Model)) {
                $mountedModelCache[$prop.Model] = $null -ne (Read-VpkSearchPathFile -SearchPath $searchPath -VirtualPath $prop.Model -MaxBytes 8)
            }
            if (-not $mountedModelCache[$prop.Model]) { $missingDetailModels[$prop.Model] = $true; continue }
            if (-not $detailModelIndex.ContainsKey($prop.Model)) {
                $detailModelIndex[$prop.Model] = $detailModels.Count
                $detailModels.Add($prop.Model)
            }
            # [model index, x, y, z, pitch, yaw, roll, skin, kind] in recipe world units and degrees.
            $props.Add(@($detailModelIndex[$prop.Model], (Format-SkyNumber $prop.Origin.X), (Format-SkyNumber $prop.Origin.Y), (Format-SkyNumber $prop.Origin.Z),
                (Format-SkyNumber $prop.Angles.X), (Format-SkyNumber $prop.Angles.Y), (Format-SkyNumber $prop.Angles.Z), $prop.Skin, $prop.Kind))
            if ($prop.Kind -eq 2) { $totalGeneratedCars++ }
        }
        $fires = [System.Collections.Generic.List[object]]::new()
        foreach ($fire in $detail.Fires) {
            $fires.Add(@((Format-SkyNumber $fire.Origin.X), (Format-SkyNumber $fire.Origin.Y), (Format-SkyNumber $fire.Origin.Z), $fire.Kind))
        }
        $totalDetailProps += $props.Count
        $totalFireCandidates += $fires.Count
        $detailRecipes[[System.IO.Path]::GetFileNameWithoutExtension($recipePath).ToLowerInvariant()] = [ordered]@{ props = $props.ToArray(); fires = $fires.ToArray() }
    }
}
$manifest = [ordered]@{
    schemaVersion = $manifestSchemaVersion
    profile = $profileName
    builderVersion = $builderVersion
    scale = $skyScale
    cellSpan = $cellSpan
    neighbourRadius = $neighbourRadius
    skylineRadius = $skylineRadius
    maxTowerModels = $maxTowerModels
    cameraOrigin = @(0, 0, $cameraZ)
    recipes = $recipeModels
    # Optional snow overlays per recipe; older runtimes ignore this table.
    snow = $recipeSnowModels
    # Tower-only geometry retains instance positions without roads, scenery props or fire candidates.
    towers = $recipeTowerModels
    # Optional set dressing (props, road wrecks, fire candidates); older runtimes ignore this table.
    detail = [ordered]@{ models = $detailModels.ToArray(); recipes = $detailRecipes }
}
$manifestPath = Join-Path $contentDirectory "data_static\zombiesim_skybox_$profileName.json"
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath)
$manifestText = $manifest | ConvertTo-Json -Depth 8 -Compress
if (-not (Test-Path -LiteralPath $manifestPath) -or (Get-Content -Raw -LiteralPath $manifestPath) -ne $manifestText) {
    [System.IO.File]::WriteAllText($manifestPath, $manifestText, [System.Text.UTF8Encoding]::new($false))
}

$reportPath = Join-Path $outputRoot 'skybox-models-report.json'
$report = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    profile = $profileName
    plan = $PlanData
    recipes = $recipePaths.Count
    parts = $totalParts
    triangles = $totalTriangles
    snowParts = $totalSnowParts
    snowTriangles = $totalSnowTriangles
    towerParts = $totalTowerParts
    towerTriangles = $totalTowerTriangles
    detailModels = $detailModels.Count
    detailProps = $totalDetailProps
    generatedRoadCars = $totalGeneratedCars
    fireCandidates = $totalFireCandidates
    missingDetailModels = @($missingDetailModels.Keys | Sort-Object)
    prunedModelFiles = $prunedModels
    manifest = if ($manifestPath.StartsWith($projectRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $manifestPath.Substring($projectRoot.Length).TrimStart('\')
    } else { $manifestPath }
    materials = $materialReport.ToArray()
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$skipped = @($materialReport | Where-Object { $_.status -ne 'ok' -and $_.status -ne 'skipped-tool' })
Write-Host ("Skybox manifest: {0} ({1} recipes, {2} model parts, {3} triangles, {4} snow parts, {5} snow triangles, {6} non-tool materials skipped, {7} stale model files pruned)" -f $manifestPath, $recipePaths.Count, $totalParts, $totalTriangles, $totalSnowParts, $totalSnowTriangles, $skipped.Count, $prunedModels)
Write-Host ("Skybox detail: {0} props ({1} generated road wrecks) from {2} models, {3} fire candidates, {4} unmounted models skipped" -f $totalDetailProps, $totalGeneratedCars, $detailModels.Count, $totalFireCandidates, $missingDetailModels.Count)