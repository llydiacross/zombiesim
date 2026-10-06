param([string[]]$UvGuideModels = @(),
    [ValidateSet('group01', 'group02', 'group03')][string[]]$ModelGroups = @('group01'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'vpk_reader.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$gameRoot = (Resolve-Path (Join-Path $root '..\..\..')).Path
$search = New-VpkSearchPath -LooseDirectories @((Join-Path $gameRoot 'garrysmod')) -VpkPaths @(
    (Join-Path $gameRoot 'garrysmod\garrysmod_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\hl2_misc_dir.vpk'),
    (Join-Path $gameRoot 'sourceengine\hl2_textures_dir.vpk')
)
$output = Join-Path $root 'generated\clothing_preview'
$null = New-Item -ItemType Directory -Force -Path $output
$reportName = if (($ModelGroups -join ',') -eq 'group01') { 'model-inspection.json' }
    else { 'model-inspection-' + ($ModelGroups -join '-') + '.json' }
$reportPath = Join-Path $output $reportName
foreach ($requested in $UvGuideModels) {
    if ($requested -notmatch '^models/player/(group01|group03)/(male|female)_\d{2}\.mdl$' -or
        $Matches[1] -notin $ModelGroups) {
        throw "UV guide model is not in a supported selected model group: $requested"
    }
}
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
function Read-Asset([string]$Path) {
    $entry = Read-VpkSearchPathFile $search $Path
    if ($null -eq $entry) { throw "Mounted clothing asset is missing: $Path" }
    return $entry
}
function Read-Int([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) { throw "Invalid model integer offset: $Offset" }
    return [BitConverter]::ToInt32($Bytes, $Offset)
}
function Read-String([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset -ge $Bytes.Length) { throw "Invalid model string offset: $Offset" }
    $end = $Offset
    while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) { $end++ }
    if ($end -eq $Bytes.Length) { throw 'Unterminated mounted model string.' }
    return [Text.Encoding]::UTF8.GetString($Bytes, $Offset, $end - $Offset)
}
function Write-UvGuide([string]$ModelPath, [byte[]]$Mdl, [byte[]]$Vvd, [int[]]$Indices,
    [int]$VertexData, [int]$BodyIndex, [int]$SubmodelIndex, [int]$MeshIndex, [int]$FirstVertex, [int]$VertexCount,
    [int]$Size) {
    Add-Type -AssemblyName System.Drawing
    $vtx = (Read-Asset ($ModelPath.Substring(0, $ModelPath.Length - 4) + '.dx90.vtx')).Bytes
    if ((Read-Int $vtx 0) -ne 7 -or (Read-Int $vtx 16) -ne (Read-Int $Mdl 8)) {
        throw "VTX version/checksum mismatch: $ModelPath"
    }
    if ($BodyIndex -ge (Read-Int $vtx 28)) { throw "Invalid VTX body index: $ModelPath" }
    $part = (Read-Int $vtx 32) + 8 * $BodyIndex
    if ($SubmodelIndex -ge (Read-Int $vtx $part)) { throw "Invalid VTX submodel index: $ModelPath" }
    $model = $part + (Read-Int $vtx ($part + 4)) + 8 * $SubmodelIndex
    if ((Read-Int $vtx $model) -lt 1) { throw "No VTX root LOD: $ModelPath" }
    $lod = $model + (Read-Int $vtx ($model + 4))
    if ($MeshIndex -ge (Read-Int $vtx $lod)) { throw "Invalid VTX mesh index: $ModelPath" }
    $mesh = $lod + (Read-Int $vtx ($lod + 4)) + 9 * $MeshIndex
    $groupCount = Read-Int $vtx $mesh
    $groupStart = $mesh + (Read-Int $vtx ($mesh + 4))
    if ($Size -notin 1024, 2048) { throw "Unsupported clothing chart size: $Size" }
    $guide = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($guide)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(200, 232, 235, 239), 1)
    $gridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 228, 132, 50), 1)
    $font = [System.Drawing.Font]::new('Arial', 16, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $triangles = 0
    $neckline = [System.Collections.Generic.List[object]]::new()
    $sleeves = [System.Collections.Generic.List[object]]::new()
    $legs = [System.Collections.Generic.List[object]]::new()
    $torso = [System.Collections.Generic.List[object]]::new()
    $bodyTriangles = [System.Collections.Generic.List[object]]::new()
    $groupName = $ModelPath.Split('/')[2]
    $guideName = if ($groupName -eq 'group01') { 'uv_' } else { 'uv_' + $groupName + '_' }
    $guidePath = Join-Path $output ($guideName + [System.IO.Path]::GetFileNameWithoutExtension($ModelPath) + ".png")
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(22, 25, 30))
        for ($g = 0; $g -lt $groupCount; $g++) {
            $group = $groupStart + 25 * $g
            $groupVertices = Read-Int $vtx $group
            $vertices = $group + (Read-Int $vtx ($group + 4))
            $groupIndices = Read-Int $vtx ($group + 8)
            $indexData = $group + (Read-Int $vtx ($group + 12))
            $stripCount = Read-Int $vtx ($group + 16)
            $stripStart = $group + (Read-Int $vtx ($group + 20))
            for ($s = 0; $s -lt $stripCount; $s++) {
                $strip = $stripStart + 27 * $s
                $count = Read-Int $vtx $strip
                $firstIndex = Read-Int $vtx ($strip + 4)
                if ($firstIndex -lt 0 -or $count -lt 0 -or $firstIndex + $count -gt $groupIndices) {
                    throw "Invalid VTX strip index range: $ModelPath"
                }
                $flags = $vtx[$strip + 18]
                if (($flags -band 1) -eq 0 -or $count % 3 -ne 0) {
                    throw "UV guide supports verified triangle-list strips only: $ModelPath"
                }
                for ($t = 0; $t -lt $count; $t += 3) {
                    $points = [System.Drawing.PointF[]]::new(3)
                    $positions = @()
                    for ($corner = 0; $corner -lt 3; $corner++) {
                        $index = [BitConverter]::ToUInt16($vtx, $indexData + 2 * ($firstIndex + $t + $corner))
                        if ($index -ge $groupVertices) { throw "Invalid VTX group vertex index: $ModelPath" }
                        $original = [BitConverter]::ToUInt16($vtx, $vertices + 9 * $index + 4)
                        if ($original -ge $VertexCount) { throw "Invalid VTX original vertex index: $ModelPath" }
                        $vertex = $VertexData + $Indices[$FirstVertex + $original] * 48
                        $u = [BitConverter]::ToSingle($Vvd, $vertex + 40)
                        $v = [BitConverter]::ToSingle($Vvd, $vertex + 44)
                        if ([single]::IsNaN($u) -or [single]::IsNaN($v) -or $u -lt 0 -or $u -gt 1 -or $v -lt 0 -or $v -gt 1) {
                            throw "Invalid guide UV coordinates: $ModelPath"
                        }
                        $points[$corner] = [System.Drawing.PointF]::new($u * ($Size - 1), $v * ($Size - 1))
                        $positions += ,@(
                            [BitConverter]::ToSingle($Vvd, $vertex + 16),
                            [BitConverter]::ToSingle($Vvd, $vertex + 20),
                            [BitConverter]::ToSingle($Vvd, $vertex + 24))
                    }
                    $graphics.DrawPolygon($pen, $points)
                    $center = @(0.0, 0.0, 0.0)
                    foreach ($position in $positions) {
                        for ($axis = 0; $axis -lt 3; $axis++) { $center[$axis] += $position[$axis] / 3 }
                    }
                    if ($groupName -ne 'group01') {
                        $bodyTriangles.Add([pscustomobject]@{
                            center = $center; positions = $positions
                            uv = @($points | ForEach-Object { $_.X; $_.Y })
                        })
                    }
                    if ([math]::Abs($center[0]) -lt 3 -and $center[1] -lt -1 -and $center[2] -gt 48 -and $center[2] -lt 61) {
                        $neckline.Add([pscustomobject]@{
                            center = $center
                            uv = @($points | ForEach-Object { @([math]::Round($_.X, 2), [math]::Round($_.Y, 2)) })
                        })
                    }
                    if ([math]::Abs($center[0]) -gt 8 -and $center[2] -gt 40 -and $center[2] -lt 58) {
                        $sleeves.Add([pscustomobject]@{
                            center = $center
                            uvCenter = @([math]::Round(($points[0].X + $points[1].X + $points[2].X) / 3, 2),
                                [math]::Round(($points[0].Y + $points[1].Y + $points[2].Y) / 3, 2))
                        })
                    }
                    if ($center[2] -gt 6 -and $center[2] -lt 37 -and [math]::Abs($center[0]) -gt 2) {
                        $legs.Add([pscustomobject]@{
                            center = $center
                            uvCenter = @([math]::Round(($points[0].X + $points[1].X + $points[2].X) / 3, 2),
                                [math]::Round(($points[0].Y + $points[1].Y + $points[2].Y) / 3, 2))
                        })
                    }
                    if ($center[2] -gt 37 -and $center[2] -lt 61 -and [math]::Abs($center[0]) -lt 14) {
                        $torso.Add([pscustomobject]@{
                            center = $center
                            positions = $positions
                            uv = @($points | ForEach-Object { $_.X; $_.Y })
                        })
                    }
                    $triangles++
                }
            }
        }
        if ($triangles -lt 1) { throw "UV guide contains no body triangles: $ModelPath" }
        for ($i = 0; $i -lt 8; $i++) {
            $step = [int]($Size / 8)
            $graphics.DrawLine($gridPen, $i * $step, 0, $i * $step, $Size - 1)
            $graphics.DrawLine($gridPen, 0, $i * $step, $Size - 1, $i * $step)
            for ($j = 0; $j -lt 8; $j++) {
                $graphics.DrawString(([string][char](65 + $i) + ($j + 1)), $font,
                    [System.Drawing.Brushes]::Orange, $j * $step + 4, $i * $step + 4)
            }
        }
        $guide.Save($guidePath, [System.Drawing.Imaging.ImageFormat]::Png)
        if ($groupName -ne 'group01') {
            [pscustomobject]@{
                schemaVersion = 1; model = $ModelPath; size = $Size
                garmentMasksVerified = $false; triangles = $bodyTriangles.ToArray()
            } | ConvertTo-Json -Depth 7 |
                Set-Content -LiteralPath ([IO.Path]::ChangeExtension($guidePath, '.bodytriangles.json')) -Encoding UTF8
        }
        $neckline.ToArray() | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($guidePath, '.neckline.json')) -Encoding UTF8
        $sleeves.ToArray() | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($guidePath, '.sleeves.json')) -Encoding UTF8
        $legs.ToArray() | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($guidePath, '.legs.json')) -Encoding UTF8
        $torso.ToArray() | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($guidePath, '.torso.json')) -Encoding UTF8
    } finally {
        $font.Dispose(); $gridPen.Dispose(); $pen.Dispose(); $graphics.Dispose(); $guide.Dispose()
    }
    return [pscustomobject]@{ path = $guidePath; triangles = $triangles; topologyVersion = 7; size = $Size; garmentMasksVerified = $false }
}
$rules = Get-Content -LiteralPath (Join-Path $root 'gamemode\sh_characters.lua') -Raw
if ($rules -notmatch 'models/player/group01/' -or $rules -notmatch 'gender == "male" and 9 or 6') {
    throw 'Character model allowlist changed; update the clothing inspector before using its findings.'
}
$models = foreach ($group in ($ModelGroups | Select-Object -Unique)) {
foreach ($sex in 'male', 'female') {
    $count = if ($sex -eq 'male') { 9 } else { 6 }
    for ($number = 1; $number -le $count; $number++) {
        $path = 'models/player/{0}/{1}_{2:D2}.mdl' -f $group, $sex, $number
        $entry = Read-Asset $path
        $mdl = $entry.Bytes
        if ([Text.Encoding]::ASCII.GetString($mdl, 0, 4) -ne 'IDST' -or (Read-Int $mdl 4) -ne 48) {
            throw "Unsupported MDL header/version: $path"
        }
        if ((Read-Int $mdl 76) -ne $mdl.Length) { throw "MDL length mismatch: $path" }
        $textureCount = Read-Int $mdl 204
        $textureOffset = Read-Int $mdl 208
        $directoryCount = Read-Int $mdl 212
        $directoryOffset = Read-Int $mdl 216
        $skinReferences = Read-Int $mdl 220
        $skinCount = Read-Int $mdl 224
        $skinOffset = Read-Int $mdl 228
        $bodyCount = Read-Int $mdl 232
        $bodyOffset = Read-Int $mdl 236
        if ($textureCount -lt 1 -or $textureCount -gt 64 -or $directoryCount -lt 1 -or
            $directoryCount -gt 64 -or $bodyCount -lt 1 -or $bodyCount -gt 64 -or
            $skinReferences -lt 1 -or $skinCount -lt 1) { throw "Invalid MDL tables: $path" }
        $directories = for ($i = 0; $i -lt $directoryCount; $i++) {
            Read-String $mdl (Read-Int $mdl ($directoryOffset + 4 * $i))
        }
        $textures = for ($i = 0; $i -lt $textureCount; $i++) {
            $offset = $textureOffset + 64 * $i
            Read-String $mdl ($offset + (Read-Int $mdl $offset))
        }
        $materials = foreach ($texture in $textures) {
            $material = $null
            foreach ($directory in $directories) {
                $virtual = ('materials/' + $directory.TrimEnd('/', '\') + '/' + $texture + '.vmt').Replace('\', '/')
                $candidate = Read-VpkSearchPathFile $search $virtual
                if ($null -ne $candidate) { $material = $candidate; break }
            }
            if ($null -eq $material) { throw "Cannot resolve mounted model material: $path / $texture" }
            $text = [Text.Encoding]::UTF8.GetString($material.Bytes)
            $baseMatch = [regex]::Match($text, '(?im)"?\$basetexture"?\s+"?([^"\s]+)')
            $base = if ($baseMatch.Success) { $baseMatch.Groups[1].Value } else { '' }
            $width = 0; $height = 0
            if ($base) {
                $vtf = Read-Asset "materials/$base.vtf"
                $width = [BitConverter]::ToUInt16($vtf.Bytes, 16)
                $height = [BitConverter]::ToUInt16($vtf.Bytes, 18)
            }
            [pscustomobject]@{
                name = $texture; path = $virtual.Substring(10, $virtual.Length - 14)
                baseTexture = $base; width = $width; height = $height
                playerColourProxy = $text -match '(?i)PlayerColor'
            }
        }
        $vvd = (Read-Asset ($path.Substring(0, $path.Length - 4) + '.vvd')).Bytes
        if ([Text.Encoding]::ASCII.GetString($vvd, 0, 4) -ne 'IDSV' -or (Read-Int $vvd 4) -ne 4 -or
            (Read-Int $mdl 8) -ne (Read-Int $vvd 8)) { throw "MDL/VVD version or checksum mismatch: $path" }
        $vertexCount = Read-Int $vvd 16
        $fixupCount = Read-Int $vvd 48
        $fixupOffset = Read-Int $vvd 52
        $vertexOffset = Read-Int $vvd 56
        $indices = [System.Collections.Generic.List[int]]::new()
        if ($fixupCount -gt 0) {
            for ($i = 0; $i -lt $fixupCount; $i++) {
                $offset = $fixupOffset + 12 * $i
                $source = Read-Int $vvd ($offset + 4)
                $countVertices = Read-Int $vvd ($offset + 8)
                if ($source -lt 0 -or $countVertices -lt 0 -or $source + $countVertices -gt $vertexCount) {
                    throw "Invalid VVD fixup: $path"
                }
                for ($j = 0; $j -lt $countVertices; $j++) { $indices.Add($source + $j) }
            }
        } else {
            for ($i = 0; $i -lt $vertexCount; $i++) { $indices.Add($i) }
        }
        if ($indices.Count -ne $vertexCount) { throw "VVD root-LOD fixup count mismatch: $path" }
        $bodygroups = foreach ($body in 0..($bodyCount - 1)) {
            $part = $bodyOffset + 16 * $body
            $partName = Read-String $mdl ($part + (Read-Int $mdl $part))
            $submodelCount = Read-Int $mdl ($part + 4)
            $modelOffset = $part + (Read-Int $mdl ($part + 12))
            $submodels = for ($sub = 0; $sub -lt $submodelCount; $sub++) {
                $model = $modelOffset + 148 * $sub
                $meshCount = Read-Int $mdl ($model + 72)
                $meshOffset = $model + (Read-Int $mdl ($model + 76))
                $modelVertexOffset = Read-Int $mdl ($model + 84)
                if ($modelVertexOffset % 48 -ne 0) { throw "Unaligned MDL vertex offset: $path" }
                $meshes = for ($meshIndex = 0; $meshIndex -lt $meshCount; $meshIndex++) {
                    $mesh = $meshOffset + 116 * $meshIndex
                    $reference = Read-Int $mdl $mesh
                    if ($reference -lt 0 -or $reference -ge $skinReferences) { throw "Invalid skin reference: $path" }
                    $materialIndex = [BitConverter]::ToUInt16($mdl, $skinOffset + 2 * $reference)
                    if ($materialIndex -ge $textureCount) { throw "Invalid mesh material index: $path" }
                    $countVertices = Read-Int $mdl ($mesh + 8)
                    $first = [int]($modelVertexOffset / 48) + (Read-Int $mdl ($mesh + 12))
                    if ($first -lt 0 -or $countVertices -lt 0 -or $first + $countVertices -gt $vertexCount) {
                        throw "Invalid mesh vertex range: $path"
                    }
                    $minimum = @( [double]::PositiveInfinity, [double]::PositiveInfinity, [double]::PositiveInfinity )
                    $maximum = @( [double]::NegativeInfinity, [double]::NegativeInfinity, [double]::NegativeInfinity )
                    $uvMin = @([double]::PositiveInfinity, [double]::PositiveInfinity)
                    $uvMax = @([double]::NegativeInfinity, [double]::NegativeInfinity)
                    $uvBytes = [System.Collections.Generic.List[byte]]::new()
                    for ($v = 0; $v -lt $countVertices; $v++) {
                        $vertex = $vertexOffset + $indices[$first + $v] * 48
                        if ($vertex + 48 -gt $vvd.Length) { throw "Truncated VVD: $path" }
                        for ($axis = 0; $axis -lt 3; $axis++) {
                            $value = [BitConverter]::ToSingle($vvd, $vertex + 16 + 4 * $axis)
                            $minimum[$axis] = [math]::Min($minimum[$axis], $value)
                            $maximum[$axis] = [math]::Max($maximum[$axis], $value)
                        }
                        for ($axis = 0; $axis -lt 2; $axis++) {
                            $value = [BitConverter]::ToSingle($vvd, $vertex + 40 + 4 * $axis)
                            $uvMin[$axis] = [math]::Min($uvMin[$axis], $value)
                            $uvMax[$axis] = [math]::Max($uvMax[$axis], $value)
                        }
                        $uvBytes.AddRange([byte[]]$vvd[($vertex + 40)..($vertex + 47)])
                    }
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try { $uvHash = [BitConverter]::ToString($sha.ComputeHash($uvBytes.ToArray())).Replace('-', '') }
                    finally { $sha.Dispose() }
                    $uvGuide = $null
                    if ($path -in $UvGuideModels -and $materials[$materialIndex].name -eq 'players_sheet') {
                        $uvGuide = Write-UvGuide $path $mdl $vvd $indices.ToArray() $vertexOffset $body $sub $meshIndex $first $countVertices $materials[$materialIndex].width
                    }
                    [pscustomobject]@{
                        materialIndex = $materialIndex; material = $materials[$materialIndex].path
                        vertices = $countVertices; positionMin = $minimum; positionMax = $maximum
                        uvMin = $uvMin; uvMax = $uvMax; uvSequenceSha256 = $uvHash; uvGuide = $uvGuide
                    }
                }
                [pscustomobject]@{ name = Read-String $mdl $model; meshes = @($meshes) }
            }
            [pscustomobject]@{ id = $body; name = $partName; choices = $submodelCount; submodels = @($submodels) }
        }
        [pscustomobject]@{
            model = $path; source = $entry.Source; mdlVersion = 48; skinCount = $skinCount
            materials = @($materials); vertices = $vertexCount; bodygroups = @($bodygroups)
        }
    }
}
}
foreach ($requested in $UvGuideModels) {
    if ($requested -notin $models.model) { throw "UV guide model is not in the selected model groups: $requested" }
}
$report = [pscustomobject]@{
    schemaVersion = 1
    reference = 'Source SDK 2013 studio.h b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474; related layout, not exact GMod engine'
    scope = 'Read-only mounted model/material metadata and UV bounds/hashes; no model/texture extraction, no authored UV masks or runtime proof'
    models = @($models)
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
foreach ($model in $models) {
    Write-Host "$($model.model): $($model.vertices) vertices; $($model.skinCount) skins; materials $($model.materials.path -join ', ')"
}
Write-Host "Inspected $($models.Count) mounted citizen player models without copying model or texture assets."
