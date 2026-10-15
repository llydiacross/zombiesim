param(
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [string]$Output = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path (Join-Path $root $profile.Settings.paths.templateDirectory) 'roads\motorway_3x1'
$names = @(
    'tile_motorway.vmf', 'tile_motorway_road_bridge.vmf',
    'tile_motorway_corner_5x3.vmf', 'tile_motorway_crossroads_6x3.vmf',
    'tile_motorway_tjunction_6x3.vmf', 'tile_motorway_deadend_3x3.vmf',
    'tile_motorway_onramp_3x4.vmf', 'tile_motorway_onramp_dual_3x4.vmf'
)
$pieces = foreach ($name in $names) {
    $path = Join-Path $directory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Motorway survey source missing: $path" }
    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([System.IO.File]::ReadAllText($path))
    $world = $tree.Child('world')
    if ($null -eq $world) { throw "Motorway survey source has no world: $path" }
    $owners = @($world) + @($tree.Children | Where-Object Name -eq 'entity')
    $faces = [System.Collections.Generic.List[object]]::new()
    $points = [System.Collections.Generic.List[object]]::new()
    $entities = [System.Collections.Generic.List[object]]::new()
    $solidCount = 0
    foreach ($owner in $owners) {
        if ($owner.Name -eq 'entity') {
            $entities.Add([ordered]@{
                id = $owner.Get('id'); classname = $owner.Get('classname')
                origin = $owner.Get('origin'); angles = $owner.Get('angles')
                model = $owner.Get('model'); targetname = $owner.Get('targetname')
            })
        }
        foreach ($solid in @($owner.Children | Where-Object Name -eq 'solid')) {
            $solidCount++
            foreach ($side in @($solid.Children | Where-Object Name -eq 'side')) {
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw "Missing Hammer++ winding: $name solid $($solid.Get('id')) side $($side.Get('id'))." }
                $vertices = @($winding.GetAll('v') | ForEach-Object {
                    $v = [ZombieSim.Skybox.Vec3]::Parse($_)
                    if ([double]::IsNaN($v.X) -or [double]::IsInfinity($v.X) -or [double]::IsNaN($v.Y) -or [double]::IsInfinity($v.Y) -or [double]::IsNaN($v.Z) -or [double]::IsInfinity($v.Z)) {
                        throw "Non-finite Hammer++ winding: $name side $($side.Get('id'))."
                    }
                    [pscustomobject]@{ x = $v.X; y = $v.Y; z = $v.Z }
                })
                if ($vertices.Count -lt 3) { throw "Incomplete Hammer++ winding: $name side $($side.Get('id'))." }
                foreach ($vertex in $vertices) { $points.Add($vertex) }
                $zValues = @($vertices | ForEach-Object z | Sort-Object -Unique)
                $faces.Add([ordered]@{
                    ownerId = $owner.Get('id'); classname = $owner.Get('classname')
                    solidId = $solid.Get('id'); sideId = $side.Get('id')
                    material = $side.Get('material')
                    displacement = $null -ne $side.Child('dispinfo')
                    horizontal = $zValues.Count -eq 1
                    vertices = $vertices
                })
            }
        }
    }
    if ($points.Count -eq 0) { throw "Motorway survey source has no winding vertices: $path" }
    $bounds = [ordered]@{}
    foreach ($axis in @('x', 'y', 'z')) {
        $range = $points | Measure-Object -Property $axis -Minimum -Maximum
        $bounds[$axis] = [ordered]@{ min = $range.Minimum; max = $range.Maximum }
    }
    $width = $null
    $height = $null
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    if ($stem -match '_(\d+)x(\d+)$') {
        $width = [int]$Matches[1]
        $height = [int]$Matches[2]
    }
    $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($before -cne $after) { throw "Motorway source changed during survey: $path. Save/reconcile authoring before retrying." }
    [ordered]@{
        source = $path; sha256 = $after
        namedFootprint = [ordered]@{ width = $width; height = $height; verified = $false }
        windingBounds = $bounds
        solidCount = $solidCount; faceCount = $faces.Count
        faces = @($faces); entities = @($entities)
        ports = @(); portsStatus = 'requires_authored_and_Hammer_review'
    }
}
$report = [ordered]@{
    schemaVersion = 1; profile = $profile.Name
    scope = 'Authored saved Hammer++ face windings only; not brush reconstruction, prop/model bounds, displacement tessellation, compiled collision or verified driveable ports.'
    pieces = @($pieces)
}
if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $fullOutput = [System.IO.Path]::GetFullPath($Output)
    if ([System.IO.Path]::GetExtension($fullOutput) -ine '.json') { throw 'Motorway survey output must be a JSON report.' }
    if (@($pieces | Where-Object { [string]$_.source -ieq $fullOutput }).Count -gt 0) { throw 'Motorway survey cannot overwrite an authored source.' }
    [System.IO.File]::WriteAllText($fullOutput, ($report | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
}
foreach ($piece in $pieces) {
    [pscustomobject]@{
        template = [System.IO.Path]::GetFileName($piece.source)
        namedFootprint = if ($null -ne $piece.namedFootprint.width) { "$($piece.namedFootprint.width)x$($piece.namedFootprint.height)" } else { 'unsuffixed/unverified' }
        solids = $piece.solidCount; faces = $piece.faceCount
        x = "$($piece.windingBounds.x.min)..$($piece.windingBounds.x.max)"
        y = "$($piece.windingBounds.y.min)..$($piece.windingBounds.y.max)"
        z = "$($piece.windingBounds.z.min)..$($piece.windingBounds.z.max)"
    }
}
