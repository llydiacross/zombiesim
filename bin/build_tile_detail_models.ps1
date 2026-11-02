[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string[]]$Name,
    [switch]$Force
)

# Compiles the func_detail brushes of selected tile sources into static models and writes
# the generator-facing tile (world shell brushes + prop_static + info_lighting).
# The editable source stays in tiletemplates_modelsrc; never hand-edit the generated tile.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'vpk_reader.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force

$root = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $root 'tiletemplates_modelsrc'
$tileRoot = Join-Path $root 'tiletemplates'
if (-not $ConfigPath) { $ConfigPath = Join-Path $sourceRoot 'detail_models.json' }
$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
if ($config.schema -ne 1) { throw "Unsupported detail-model config schema: $($config.schema)" }

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
$utf8 = [Text.UTF8Encoding]::new($false)
$contentModels = Join-Path $root 'content\models\zombiesim\tiles'
$contentMaterials = Join-Path $root 'content\materials\models\zombiesim\tiles'
$modelExtensions = @('.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx', '.sw.vtx', '.phy')

function F([double]$value) { $value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }

function Split-VmfBlocks([string[]]$lines) {
    $blocks = [Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $lines.Count) {
        if ($lines[$i].Trim() -eq '') { $i++; continue }
        if ($lines[$i] -notmatch '^[A-Za-z_]+$' -or $i + 1 -ge $lines.Count -or $lines[$i + 1] -ne '{') {
            throw "Unexpected top-level VMF line $($i + 1): $($lines[$i])"
        }
        $depth = 0; $start = $i; $i++
        do {
            if ($i -ge $lines.Count) { throw "Unterminated VMF block starting at line $($start + 1)" }
            $trimmed = $lines[$i].Trim()
            if ($trimmed -eq '{') { $depth++ } elseif ($trimmed -eq '}') { $depth-- }
            $i++
        } while ($depth -gt 0)
        $body = $lines[$start..($i - 1)]
        $class = $null
        foreach ($line in $body) { if ($line -match '^\t"classname" "([^"]*)"$') { $class = $Matches[1]; break } }
        $blocks.Add([pscustomobject]@{ Name = $lines[$start]; Class = $class; Lines = $body })
    }
    return $blocks
}

function Get-MaterialMap($materials, [string]$prefix, [string]$label) {
    $map = [Collections.Generic.Dictionary[string, ZombieSim.Skybox.MaterialInfo]]::new([StringComparer]::OrdinalIgnoreCase)
    $reports = [Collections.Generic.List[object]]::new()
    foreach ($material in @($materials | Sort-Object)) {
        $name = $material.ToLowerInvariant().Replace('\', '/')
        if ($name.StartsWith('tools/')) { throw "${label}: detail brushes use tool material $name; keep tool brushes as world geometry." }
        $vmt = Read-VpkSearchPathFile -SearchPath $search -VirtualPath "materials/$name.vmt"
        if ($null -eq $vmt) { throw "${label}: mounted material is missing: $name" }
        $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([Text.Encoding]::UTF8.GetString($vmt.Bytes))
        if ($tree.Children.Count -ne 1) { throw "${label}: unexpected material layout: $name" }
        $shader = $tree.Children[0].Name
        if ($shader -inotin @('LightmappedGeneric', 'WorldVertexTransition')) {
            throw "${label}: unsupported material shader $shader for $name; do not guess its model equivalent."
        }
        $values = @{}
        foreach ($pair in $tree.Children[0].Keys) { $values[$pair.Key.ToLowerInvariant()] = [string]$pair.Value }
        $texture = $values['$basetexture']
        if ([string]::IsNullOrWhiteSpace($texture)) { throw "${label}: material has no base texture: $name" }
        $texture = $texture.ToLowerInvariant().Replace('\', '/')
        $vtf = Read-VpkSearchPathFile -SearchPath $search -VirtualPath "materials/$texture.vtf" -MaxBytes 32
        if ($null -eq $vtf -or $vtf.Bytes.Length -lt 20 -or
            $vtf.Bytes[0] -ne 86 -or $vtf.Bytes[1] -ne 84 -or $vtf.Bytes[2] -ne 70 -or $vtf.Bytes[3] -ne 0) {
            throw "${label}: mounted texture is missing or invalid: $texture"
        }
        $width = [BitConverter]::ToUInt16($vtf.Bytes, 16)
        $height = [BitConverter]::ToUInt16($vtf.Bytes, 18)
        if ($width -eq 0 -or $height -eq 0) { throw "${label}: texture has invalid dimensions: $texture" }
        $info = [ZombieSim.Skybox.MaterialInfo]::new()
        $info.ModelMaterial = $prefix + ($name -replace '[^a-z0-9]+', '_')
        $info.Width = $width
        $info.Height = $height
        $map.Add($material, $info)
        $reports.Add([pscustomobject]@{
            source = $name; shader = $shader; material = $info.ModelMaterial; texture = $texture
            alphaTest = $values['$alphatest']; translucent = $values['$translucent']; noCull = $values['$nocull']
            alphaTestReference = $values['$alphatestreference']
            note = if ($shader -eq 'WorldVertexTransition') { 'Blend reduced to its first base texture.' } else { $null }
        })
    }
    return @{ Map = $map; Reports = $reports }
}

function Get-CollisionBoxes([string]$detailText, [double]$slabHeight) {
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse($detailText)
    $solids = [Collections.Generic.List[double[]]]::new()
    $stack = [Collections.Generic.Stack[object]]::new()
    foreach ($node in $tree.Children) { $stack.Push($node) }
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        if ($node.Name -ieq 'solid') {
            $box = @([double]::MaxValue, [double]::MaxValue, [double]::MaxValue, [double]::MinValue, [double]::MinValue, [double]::MinValue)
            foreach ($side in $node.Children) {
                if ($side.Name -ine 'side') { continue }
                $vertices = $side.Child('vertices_plus')
                if ($null -eq $vertices) { throw 'Collision source has a side without vertices_plus.' }
                foreach ($text in $vertices.GetAll('v')) {
                    $p = [ZombieSim.Skybox.Vec3]::Parse($text)
                    $box[0] = [Math]::Min($box[0], $p.X); $box[1] = [Math]::Min($box[1], $p.Y); $box[2] = [Math]::Min($box[2], $p.Z)
                    $box[3] = [Math]::Max($box[3], $p.X); $box[4] = [Math]::Max($box[4], $p.Y); $box[5] = [Math]::Max($box[5], $p.Z)
                }
            }
            if ($box[0] -le $box[3]) { $solids.Add([double[]]$box) }
            continue
        }
        foreach ($child in $node.Children) { $stack.Push($child) }
    }
    if ($solids.Count -eq 0) { throw 'No detail solids were found for collision.' }
    $zMin = [double]::MaxValue; $zMax = [double]::MinValue
    foreach ($s in $solids) { $zMin = [Math]::Min($zMin, $s[2]); $zMax = [Math]::Max($zMax, $s[5]) }
    $boxes = [Collections.Generic.List[double[]]]::new()
    for ($slab = [Math]::Floor($zMin); $slab -lt $zMax; $slab += $slabHeight) {
        $top = $slab + $slabHeight
        $b = [double[]]@([double]::MaxValue, [double]::MaxValue, [double]::MaxValue, [double]::MinValue, [double]::MinValue, [double]::MinValue)
        $any = $false
        foreach ($s in $solids) {
            if ($s[2] -ge $top -or $s[5] -le $slab) { continue }
            $any = $true
            for ($k = 0; $k -lt 3; $k++) { $b[$k] = [Math]::Min($b[$k], $s[$k]); $b[$k + 3] = [Math]::Max($b[$k + 3], $s[$k + 3]) }
        }
        if (-not $any) { continue }
        $b[2] = [Math]::Max($slab, $b[2])
        $b[5] = [Math]::Min($top, $b[5])
        # A one-unit gap keeps stacked boxes from welding into a single concave hull.
        if ($b[5] -ge $top) { $b[5] = $top - 1 }
        if ($b[5] - $b[2] -lt 1) { continue }
        $boxes.Add($b)
    }
    return ,$boxes
}

function Get-CollisionSmd($boxes) {
    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('version 1').AppendLine('nodes').AppendLine('0 "root" -1').AppendLine('end')
    [void]$sb.AppendLine('skeleton').AppendLine('time 0').AppendLine('0 0 0 0 0 0 0').AppendLine('end').AppendLine('triangles')
    $faces = @(
        @(@(0, 0, 0), @(0, 1, 0), @(0, 1, 1), @(0, 0, 1), @(-1, 0, 0)),
        @(@(1, 0, 0), @(1, 0, 1), @(1, 1, 1), @(1, 1, 0), @(1, 0, 0)),
        @(@(0, 0, 0), @(0, 0, 1), @(1, 0, 1), @(1, 0, 0), @(0, -1, 0)),
        @(@(0, 1, 0), @(1, 1, 0), @(1, 1, 1), @(0, 1, 1), @(0, 1, 0)),
        @(@(0, 0, 0), @(1, 0, 0), @(1, 1, 0), @(0, 1, 0), @(0, 0, -1)),
        @(@(0, 0, 1), @(0, 1, 1), @(1, 1, 1), @(1, 0, 1), @(0, 0, 1))
    )
    foreach ($b in $boxes) {
        foreach ($face in $faces) {
            $corners = foreach ($c in $face[0..3]) {
                $x = if ($c[0]) { $b[3] } else { $b[0] }
                $y = if ($c[1]) { $b[4] } else { $b[1] }
                $z = if ($c[2]) { $b[5] } else { $b[2] }
                # One normal per corner so studiomdl welds each box's faces into a single convex piece;
                # per-face normals leave every face a separate 2-dimensional part.
                $n = @(((2 * $c[0] - 1) * 0.57735), ((2 * $c[1] - 1) * 0.57735), ((2 * $c[2] - 1) * 0.57735))
                # Match CellModelBuilder: studiomdl turns SMD (x, y) into model (-y, x).
                '0 {0} {1} {2} {3} {4} {5} 0 0' -f (F $y), (F (-$x)), (F $z), (F $n[1]), (F (-$n[0])), (F $n[2])
            }
            foreach ($tri in @(@(0, 1, 2), @(0, 2, 3))) {
                [void]$sb.AppendLine('phys')
                foreach ($k in $tri) { [void]$sb.AppendLine($corners[$k]) }
            }
        }
    }
    [void]$sb.AppendLine('end')
    return $sb.ToString()
}

function Invoke-ModelCompiler([string]$gameDirectory, [string]$qc, [string]$log) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = $studiomdl
    $process.StartInfo.Arguments = ('-nop4 -game "{0}" "{1}"' -f $gameDirectory.TrimEnd('\'), $qc)
    $process.StartInfo.WorkingDirectory = Split-Path -Parent $studiomdl
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    if (-not $process.Start()) { throw 'Could not start the model compiler.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $text = $stdout.Result + $stderr
    [IO.File]::WriteAllText($log, $text, $utf8)
    if ($process.ExitCode -ne 0) { throw "studiomdl failed (exit $($process.ExitCode)); see $log" }
    return $text
}

function New-EntityLines([int]$id, [Collections.Specialized.OrderedDictionary]$keys, [string]$color) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('entity'); $lines.Add('{')
    $lines.Add(('	"id" "{0}"' -f $id))
    foreach ($key in $keys.Keys) { $lines.Add(('	"{0}" "{1}"' -f $key, $keys[$key])) }
    foreach ($line in @('	editor', '	{', ('		"color" "{0}"' -f $color), '		"visgroupshown" "1"',
        '		"visgroupautoshown" "1"', '		"logicalpos" "[0 0]"', '	}', '}')) { $lines.Add($line) }
    return $lines
}

$entries = @($config.tiles)
if ($Name) { $entries = @($entries | Where-Object { $Name -contains $_.name }) }
if ($entries.Count -eq 0) { throw 'No configured detail-model tiles matched.' }
foreach ($entry in $entries) {
    $label = [string]$entry.name
    if ($label -notmatch '^[a-z0-9_]+$') { throw "Detail-model name must be lowercase alphanumeric/underscore: $label" }
    $source = Join-Path $sourceRoot ([string]$entry.source).Replace('/', '\')
    $tile = Join-Path $tileRoot ([string]$entry.tile).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "${label}: source VMF is missing: $source" }
    $work = Join-Path $root "generated\tile_detail_models\$label"
    $reportPath = Join-Path $work 'report.json'
    $previous = if (Test-Path -LiteralPath $reportPath -PathType Leaf) { Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json } else { $null }
    if ((Test-Path -LiteralPath $tile -PathType Leaf) -and -not $Force) {
        $tileHash = (Get-FileHash -LiteralPath $tile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($null -eq $previous -or $previous.tileSha256 -cne $tileHash) {
            throw "${label}: $tile was not written by this builder (or was edited by hand). Edit $source instead, or pass -Force after preserving the tile."
        }
    }

    $sourceBytes = [IO.File]::ReadAllBytes($source)
    $sourceHash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($sourceBytes)) -replace '-', '').ToLowerInvariant()
    $sourceText = $utf8.GetString($sourceBytes)
    $newline = if ($sourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $blocks = Split-VmfBlocks ($sourceText -split "\r?\n")
    $detailBlocks = @($blocks | Where-Object { $_.Name -eq 'entity' -and $_.Class -eq 'func_detail' })
    if ($detailBlocks.Count -eq 0) { throw "${label}: the source has no func_detail entities to convert." }

    $modelBase = '{0}_{1}' -f $label, $sourceHash.Substring(0, 10)
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $modelSource = Join-Path $work 'modelsrc'
    $compileGame = Join-Path $work 'game'
    if (Test-Path -LiteralPath $modelSource) { Remove-Item -LiteralPath $modelSource -Recurse -Force }
    if (Test-Path -LiteralPath $compileGame) { Remove-Item -LiteralPath $compileGame -Recurse -Force }
    $compileMaterials = Join-Path $compileGame 'materials\models\zombiesim\tiles'
    [IO.Directory]::CreateDirectory($modelSource) | Out-Null
    [IO.Directory]::CreateDirectory($compileMaterials) | Out-Null

    $detailText = (@('world', '{', '	"id" "1"', '	"classname" "worldspawn"', '}') +
        @($detailBlocks | ForEach-Object { $_.Lines })) -join $newline
    $detailPath = Join-Path $modelSource 'detail.vmf'
    [IO.File]::WriteAllText($detailPath, $detailText + $newline, $utf8)
    $mesh = [ZombieSim.Skybox.TileMeshBuilder]::Build($detailText, 0)
    if ($mesh.MissingWindings -ne 0 -or $mesh.Triangles.Count -eq 0) { throw "${label}: detail brushes are missing vertices_plus windings." }
    $materialPrefix = 'zm_tile_' + $label + '_'
    $materials = Get-MaterialMap $mesh.Materials $materialPrefix $label
    foreach ($material in $materials.Reports) {
        $vmt = [Collections.Generic.List[string]]::new()
        $vmt.Add('"VertexLitGeneric"'); $vmt.Add('{')
        $vmt.Add(('    "$basetexture" "{0}"' -f $material.texture))
        $vmt.Add(('    "$surfaceprop" "{0}"' -f $entry.surfaceProp))
        foreach ($flag in @(@('$alphatest', $material.alphaTest), @('$translucent', $material.translucent),
            @('$nocull', $material.noCull), @('$alphatestreference', $material.alphaTestReference))) {
            if ($null -ne $flag[1]) { $vmt.Add(('    "{0}" "{1}"' -f $flag[0], $flag[1])) }
        }
        $vmt.Add('}')
        [IO.File]::WriteAllText((Join-Path $compileMaterials ($material.material + '.vmt')), (($vmt -join "`r`n") + "`r`n"), $utf8)
    }

    $wrapper = Join-Path $modelSource 'wrapper.vmf'
    [IO.File]::WriteAllText($wrapper, "entity`n{`n`"classname`" `"func_instance`"`n`"file`" `"detail.vmf`"`n`"origin`" `"0 0 0`"`n`"angles`" `"0 0 0`"`n}`n", $utf8)
    $builder = [ZombieSim.Skybox.CellModelBuilder]::new(0)
    # Each part is one tile pass, so oversized detail must be split before it reaches this builder.
    $parts = @($builder.BuildParts($wrapper, 1.0, $materials.Map, 60000, 60))
    if ($parts.Count -ne 1 -or $parts[0].Triangles -ne $mesh.Triangles.Count) {
        throw "${label}: model extraction produced $($parts.Count) part(s) and $(@($parts | ForEach-Object { $_.Triangles }) -join '/') triangles; expected one part with $($mesh.Triangles.Count)."
    }
    $boxes = Get-CollisionBoxes $detailText ([double]$entry.collisionSlabHeight)
    $smd = Join-Path $modelSource "$modelBase.smd"
    [IO.File]::WriteAllText($smd, $parts[0].Smd, $utf8)
    [IO.File]::WriteAllText((Join-Path $modelSource "${modelBase}_collision.smd"), (Get-CollisionSmd $boxes), $utf8)
    $qc = Join-Path $modelSource "$modelBase.qc"
    [IO.File]::WriteAllText($qc, (@(
        ('$modelname "zombiesim/tiles/{0}.mdl"' -f $modelBase),
        '$staticprop', ('$surfaceprop "{0}"' -f $entry.surfaceProp),
        '$cdmaterials "models/zombiesim/tiles/"',
        ('$body body "{0}.smd"' -f $modelBase),
        ('$sequence idle "{0}.smd"' -f $modelBase),
        ('$collisionmodel "{0}_collision.smd"' -f $modelBase), '{',
        '    $concave', ('    $maxconvexpieces {0}' -f $boxes.Count), '}'
    ) -join "`r`n") + "`r`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $compileGame 'gameinfo.txt'), @'
"GameInfo"
{
    game "ZombieSim tile detail models"
    FileSystem
    {
        SteamAppId 4000
        SearchPaths { game |gameinfo_path|. }
    }
}
'@, $utf8)
    $log = Invoke-ModelCompiler $compileGame $qc (Join-Path $modelSource "$modelBase.log")
    if ($log -match 'ERROR|Error with convex|2-dimensional geometry') { throw "${label}: studiomdl reported an error; see $modelSource\$modelBase.log" }
    if (-not $log.Contains("Model has $($boxes.Count) convex sub-parts")) {
        throw "${label}: collision did not compile to $($boxes.Count) convex parts; see $modelSource\$modelBase.log"
    }
    $compiled = Join-Path $compileGame "models\zombiesim\tiles\$modelBase"
    foreach ($extension in @('.mdl', '.vvd', '.dx90.vtx', '.phy')) {
        if (-not (Test-Path -LiteralPath "$compiled$extension" -PathType Leaf)) { throw "${label}: compiled model is missing $extension" }
    }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sourceHash) {
        throw "${label}: the source changed during compilation; rerun the builder."
    }

    # Stage compiled outputs, removing only this tile's older model generations and materials.
    [IO.Directory]::CreateDirectory($contentModels) | Out-Null
    [IO.Directory]::CreateDirectory($contentMaterials) | Out-Null
    Get-ChildItem -LiteralPath $contentModels -File | Where-Object {
        $_.Name -like "${label}_*" -and -not $_.Name.StartsWith("$modelBase.", [StringComparison]::OrdinalIgnoreCase)
    } | Remove-Item
    Get-ChildItem -LiteralPath $contentMaterials -File -Filter "$materialPrefix*.vmt" | Remove-Item
    $staged = [Collections.Generic.List[object]]::new()
    foreach ($extension in $modelExtensions) {
        if (-not (Test-Path -LiteralPath "$compiled$extension" -PathType Leaf)) { continue }
        $target = Join-Path $contentModels "$modelBase$extension"
        Copy-Item -LiteralPath "$compiled$extension" -Destination $target -Force
        $staged.Add([pscustomobject]@{ path = $target.Substring($root.Length + 1); sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
    foreach ($material in $materials.Reports) {
        $target = Join-Path $contentMaterials ($material.material + '.vmt')
        Copy-Item -LiteralPath (Join-Path $compileMaterials ($material.material + '.vmt')) -Destination $target -Force
        $staged.Add([pscustomobject]@{ path = $target.Substring($root.Length + 1); sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() })
    }

    # Generated tile: original blocks without func_detail, plus the model and its lighting origin.
    $maxId = 0
    foreach ($match in [regex]::Matches($sourceText, '(?m)^\s*"id" "(\d+)"')) { $maxId = [Math]::Max($maxId, [int]$match.Groups[1].Value) }
    $lightName = "${label}_lighting"
    $origin = @($entry.lightingOrigin | ForEach-Object { F ([double]$_) }) -join ' '
    $newEntities = @(
        (New-EntityLines ($maxId + 1) ([ordered]@{ classname = 'info_lighting'; targetname = $lightName; origin = $origin }) '220 30 220'),
        (New-EntityLines ($maxId + 2) ([ordered]@{
            classname = 'prop_static'; angles = '0 0 0'; disableshadows = '0'; fademaxdist = '0'; fademindist = '-1'
            fadescale = '1'; lightingorigin = $lightName; model = "models/zombiesim/tiles/$modelBase.mdl"
            skin = '0'; solid = '6'; origin = '0 0 0'
        }) '255 255 0')
    )
    $output = [Collections.Generic.List[string]]::new()
    $inserted = $false
    foreach ($block in $blocks) {
        if ($block.Name -eq 'entity' -and $block.Class -eq 'func_detail') { continue }
        if (-not $inserted -and $block.Name -in @('cameras', 'cordons', 'cordon')) {
            foreach ($entity in $newEntities) { $output.AddRange([string[]]$entity) }
            $inserted = $true
        }
        $output.AddRange([string[]]$block.Lines)
    }
    if (-not $inserted) { foreach ($entity in $newEntities) { $output.AddRange([string[]]$entity) } }
    $tileText = ($output -join $newline) + $newline
    [IO.Directory]::CreateDirectory((Split-Path -Parent $tile)) | Out-Null
    $existing = if (Test-Path -LiteralPath $tile -PathType Leaf) { [IO.File]::ReadAllText($tile) } else { $null }
    if ($existing -cne $tileText) { [IO.File]::WriteAllText($tile, $tileText, $utf8) }

    $report = [pscustomobject]@{
        schema = 1; name = $label; source = $source.Substring($root.Length + 1); sourceSha256 = $sourceHash
        tile = $tile.Substring($root.Length + 1); tileSha256 = (Get-FileHash -LiteralPath $tile -Algorithm SHA256).Hash.ToLowerInvariant()
        model = "models/zombiesim/tiles/$modelBase.mdl"; detailEntities = $detailBlocks.Count
        triangles = $parts[0].Triangles; vertices = $parts[0].Vertices
        bounds = @{ min = @($parts[0].Min.X, $parts[0].Min.Y, $parts[0].Min.Z); max = @($parts[0].Max.X, $parts[0].Max.Y, $parts[0].Max.Z) }
        collisionBoxes = $boxes.Count; lightingOrigin = $origin; materials = @($materials.Reports); staged = @($staged)
        limitations = @('Collision is a stack of per-slab bounding boxes, not per-brush.',
            'The prop is vertex-lit from its info_lighting origin unless VRAD runs with -staticproplighting.')
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), $utf8)
    Write-Output $report
}

# Hammer reads the engine search paths, not content\; stage the referenced tile models there.
& (Join-Path $PSScriptRoot 'stage_hammer_assets.ps1') | Out-Host
