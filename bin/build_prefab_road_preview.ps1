param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$Compile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'vpk_reader.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force

$root = Split-Path -Parent $PSScriptRoot
$output = [IO.Path]::GetFullPath($OutputDirectory)
$generated = [IO.Path]::GetFullPath((Join-Path $root 'generated')).TrimEnd('\') + '\'
if (-not $output.StartsWith($generated, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The road reference preview must stay in an isolated generated subdirectory.'
}
if (Test-Path -LiteralPath $output) { throw "Preview output already exists; choose a fresh directory: $output" }

$source = Join-Path $root 'tiletemplates\roads\tile_road.vmf'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Road source is missing: $source" }
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$mesh = [ZombieSim.Skybox.TileMeshBuilder]::Build([IO.File]::ReadAllText($source), 0)
if ($mesh.MissingWindings -ne 0 -or $mesh.SkippedSolids -ne 0 -or $mesh.Props.Count -ne 0 -or $mesh.Triangles.Count -eq 0) {
    throw 'This prototype requires a complete, prop-free straight-road source; inspect the source before extending it.'
}

$gameRoot = (Resolve-Path -LiteralPath (Join-Path $root '..\..\..')).Path
$game = Join-Path $gameRoot 'garrysmod'
$studiomdl = Join-Path $gameRoot 'bin\studiomdl.exe'
if (-not (Test-Path -LiteralPath $studiomdl -PathType Leaf)) { throw "Model compiler is missing: $studiomdl" }
$search = New-VpkSearchPath -LooseDirectories @((Join-Path $root 'content'), $game) -VpkPaths @(
    (Join-Path $game 'garrysmod_dir.vpk'),
    (Join-Path $game 'fallbacks_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\content_cstrike_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\hl2_textures_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\hl2_misc_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\content_hl2_dir.vpk')
)
$materialMap = [Collections.Generic.Dictionary[string, ZombieSim.Skybox.MaterialInfo]]::new([StringComparer]::OrdinalIgnoreCase)
$materialReports = [Collections.Generic.List[object]]::new()
$materialPrefix = 'zm_prefab_road_' + $sourceHash.Substring(0, 12) + '_'
foreach ($material in @($mesh.Materials | Sort-Object)) {
    $name = $material.ToLowerInvariant().Replace('\', '/')
    if ($name.StartsWith('tools/')) { throw "The straight-road reference contains unsupported tool material: $name" }
    $vmt = Read-VpkSearchPathFile -SearchPath $search -VirtualPath "materials/$name.vmt"
    if ($null -eq $vmt) { throw "Mounted road material is missing: $name" }
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([Text.Encoding]::UTF8.GetString($vmt.Bytes))
    if ($tree.Children.Count -ne 1 -or $tree.Children[0].Name -ine 'LightmappedGeneric') {
        throw "Unsupported road material shader; this prototype does not guess material behavior: $name"
    }
    $values = @{}
    foreach ($pair in $tree.Children[0].Keys) { $values[$pair.Key.ToLowerInvariant()] = [string]$pair.Value }
    $texture = $values['$basetexture']
    if ([string]::IsNullOrWhiteSpace($texture)) { throw "Road material has no base texture: $name" }
    $texture = $texture.ToLowerInvariant().Replace('\', '/')
    $vtf = Read-VpkSearchPathFile -SearchPath $search -VirtualPath "materials/$texture.vtf" -MaxBytes 32
    if ($null -eq $vtf -or $vtf.Bytes.Length -lt 20 -or
        $vtf.Bytes[0] -ne 86 -or $vtf.Bytes[1] -ne 84 -or $vtf.Bytes[2] -ne 70 -or $vtf.Bytes[3] -ne 0) {
        throw "Mounted road texture is missing or invalid: $texture"
    }
    $width = [BitConverter]::ToUInt16($vtf.Bytes, 16)
    $height = [BitConverter]::ToUInt16($vtf.Bytes, 18)
    if ($width -eq 0 -or $height -eq 0) { throw "Mounted road texture has invalid dimensions: $texture" }
    $materialName = $materialPrefix + ($name -replace '[^a-z0-9]+', '_')
    $info = [ZombieSim.Skybox.MaterialInfo]::new()
    $info.ModelMaterial = $materialName
    $info.Width = $width
    $info.Height = $height
    $materialMap.Add($material, $info)
    $materialReports.Add([pscustomobject]@{
        source = $name; material = $materialName; texture = $texture; width = $width; height = $height
        alphaTest = if ($values.ContainsKey('$alphatest')) { $values['$alphatest'] } else { $null }
        translucent = if ($values.ContainsKey('$translucent')) { $values['$translucent'] } else { $null }
        noCull = if ($values.ContainsKey('$nocull')) { $values['$nocull'] } else { $null }
        alphaTestReference = if ($values.ContainsKey('$alphatestreference')) { $values['$alphatestreference'] } else { $null }
    })
}
$modelName = 'road_' + $sourceHash.Substring(0, 12) + '_v1'
$summary = [pscustomobject]@{
    source = $source; sourceSha256 = $sourceHash; triangles = $mesh.Triangles.Count
    materials = @($materialReports); model = "models/zombiesim/prefab_tile_preview/$modelName.mdl"
    limitations = @('Bottom ground faces are omitted by the shared skyline extractor.',
        'The first prototype supports the prop-free straight road only; it is not a general tile converter.')
}
if (-not $Compile) {
    Write-Output $summary
    return
}

$modelSource = Join-Path $output 'modelsrc'
$compileGame = Join-Path $output 'game'
$materialDirectory = Join-Path $compileGame 'materials\models\zombiesim\prefab_tile_preview'
[IO.Directory]::CreateDirectory($modelSource) | Out-Null
[IO.Directory]::CreateDirectory($materialDirectory) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($material in $materialReports) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('"VertexLitGeneric"')
    $lines.Add('{')
    $lines.Add(('    "$basetexture" "{0}"' -f $material.texture))
    foreach ($flag in @(
        @{ key = '$alphatest'; value = $material.alphaTest },
        @{ key = '$translucent'; value = $material.translucent },
        @{ key = '$nocull'; value = $material.noCull },
        @{ key = '$alphatestreference'; value = $material.alphaTestReference }
    )) {
        if ($null -ne $flag.value) { $lines.Add(('    "{0}" "{1}"' -f $flag.key, $flag.value)) }
    }
    $lines.Add('}')
    [IO.File]::WriteAllText((Join-Path $materialDirectory ($material.material + '.vmt')), (($lines -join "`r`n") + "`r`n"), $utf8)
}
$wrapper = Join-Path $modelSource 'road_instance.vmf'
$virtualSource = $source.Replace('\', '/')
$wrapperText = "entity`n{`n`"classname`" `"func_instance`"`n`"file`" `"$virtualSource`"`n`"origin`" `"0 0 0`"`n`"angles`" `"0 0 0`"`n}`n"
[IO.File]::WriteAllText($wrapper, $wrapperText, $utf8)
$builder = [ZombieSim.Skybox.CellModelBuilder]::new(0)
$parts = @($builder.BuildParts($wrapper, 1.0, $materialMap, 30000, 60))
if ($parts.Count -ne 1 -or $parts[0].Triangles -ne $mesh.Triangles.Count -or
    $parts[0].Min.X -ne -320 -or $parts[0].Min.Y -ne -320 -or
    $parts[0].Max.X -ne 320 -or $parts[0].Max.Y -ne 320) {
    throw 'Straight-road model geometry does not match the extracted source footprint.'
}
$smd = Join-Path $modelSource "$modelName.smd"
$qc = Join-Path $modelSource "$modelName.qc"
[IO.File]::WriteAllText($smd, $parts[0].Smd, $utf8)
$qcText = @(
    ('$modelname "zombiesim/prefab_tile_preview/{0}.mdl"' -f $modelName),
    '$staticprop', '$surfaceprop "default"',
    '$cdmaterials "models/zombiesim/prefab_tile_preview/"',
    ('$body body "{0}.smd"' -f $modelName),
    ('$sequence idle "{0}.smd"' -f $modelName)
) -join "`r`n"
[IO.File]::WriteAllText($qc, $qcText + "`r`n", $utf8)
$gameInfo = @'
"GameInfo"
{
    game "ZombieSim prefab tile preview"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths { game |gameinfo_path|. }
    }
}
'@
[IO.File]::WriteAllText((Join-Path $compileGame 'gameinfo.txt'), $gameInfo, $utf8)
$process = [Diagnostics.Process]::new()
$process.StartInfo.FileName = $studiomdl
$process.StartInfo.Arguments = ('-nop4 -game "{0}" "{1}"' -f $compileGame.TrimEnd('\'), $qc)
$process.StartInfo.WorkingDirectory = Split-Path -Parent $studiomdl
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
if (-not $process.Start()) { throw 'Could not start the model compiler.' }
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
$log = Join-Path $modelSource "$modelName.log"
[IO.File]::WriteAllText($log, $stdout + $stderr, $utf8)
$modelBase = Join-Path $compileGame "models\zombiesim\prefab_tile_preview\$modelName"
if ($process.ExitCode -ne 0) { throw "Road model compile failed (exit $($process.ExitCode)); see $log" }
foreach ($extension in @('.mdl', '.vvd', '.dx90.vtx')) {
    if (-not (Test-Path -LiteralPath "$modelBase$extension" -PathType Leaf)) {
        throw "Compiled road model is missing $extension; see $log"
    }
}
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sourceHash) {
    throw 'The road source changed during compilation; discard this isolated preview.'
}
$summary | Add-Member -NotePropertyName bounds -NotePropertyValue @{
    min = @($parts[0].Min.X, $parts[0].Min.Y, $parts[0].Min.Z)
    max = @($parts[0].Max.X, $parts[0].Max.Y, $parts[0].Max.Z)
}
[IO.File]::WriteAllText((Join-Path $output 'report.json'), ($summary | ConvertTo-Json -Depth 10), $utf8)
Write-Output $summary
