param([Parameter(Mandatory = $true)][string]$OutputDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Fixture output already exists; choose a fresh directory: $output" }
$road = Join-Path $root 'tiletemplates\roads\tile_road.vmf'
$roadHash = 'AC5D4D36CED7D546E1E9EA09CE515DFEC1939DBC1F403ED915E7B867406CF951'
if (-not (Test-Path -LiteralPath $road -PathType Leaf) -or
    (Get-FileHash -LiteralPath $road -Algorithm SHA256).Hash -cne $roadHash) {
    throw 'The approved straight-road reference source changed; rebuild and review its reference before using this fixture.'
}
$roadModel = 'models/zombiesim/prefab_tile_preview/road_ac5d4d36ced7_v1.mdl'
if (-not (Test-Path -LiteralPath (Join-Path $root "content\$($roadModel.Replace('/', '\'))") -PathType Leaf)) {
    throw 'The approved straight-road preview model is not staged.'
}
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build_sign_zoo.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "Could not parse existing fixture helpers: $errors" }
foreach ($name in @('New-ZooBox', 'New-ZooEntity')) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($definition.Count -ne 1) { throw "Missing fixture helper: $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$script:nextId = 2
function New-TestProp([string]$Id, [double]$X) {
    return [ordered]@{
        propId = $Id; model = 'models/props_c17/oildrum001.mdl'
        position = [ordered]@{ x = $X; y = 0; z = 0 }
        angles = [ordered]@{ p = 0; y = 0; r = 0 }
        skin = 0; scale = 1; movable = $false; lootMode = 'off'
    }
}
$documents = @(
    [ordered]@{
        schemaVersion = 1; id = 'zz_dev_roadblock'; name = 'TEST roadblock'
        description = 'Temporary geometry check; not approved blockade artwork.'
        tags = @('roadBlockade')
        props = @((New-TestProp 'p_left' -104), (New-TestProp 'p_center' 0), (New-TestProp 'p_right' 104))
    },
    [ordered]@{
        schemaVersion = 1; id = 'zz_dev_transition_gate'; name = 'TEST transition gate'
        description = 'Temporary open-centre arrangement; no travel trigger or gate replacement.'
        tags = @('transitionGate', 'road')
        props = @((New-TestProp 'p_left' -160), (New-TestProp 'p_right' 160))
    }
)
$brushes = @(
    (New-ZooBox -1024 -640 -32 1024 640 0),
    (New-ZooBox -1024 -640 512 1024 640 544),
    (New-ZooBox -1056 -640 -32 -1024 640 544),
    (New-ZooBox 1024 -640 -32 1056 640 544),
    (New-ZooBox -1056 -640 -32 1056 -608 544),
    (New-ZooBox -1056 608 -32 1056 640 544)
)
$entities = [Collections.Generic.List[string]]::new()
foreach ($station in @(
    @{ x = -384; tag = 'roadBlockade'; name = 'test_roadblock' },
    @{ x = 384; tag = 'transitionGate, road'; name = 'test_transition_gate' }
)) {
    $entities.Add((New-ZooEntity ([ordered]@{
        classname = 'prop_dynamic_override'; model = $roadModel
        origin = "$($station.x) 0 0"; angles = '0 0 0'; solid = '0'
    })))
    $entities.Add((New-ZooEntity ([ordered]@{
        classname = 'zn_prefab_anchor'; targetname = $station.name
        prefab_tags = $station.tag; origin = "$($station.x) 0 40"; angles = '0 0 0'
    })))
}
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'info_player_start'; origin = '0 -320 16'; angles = '0 90 0' })))
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'light'; origin = '0 0 400'; _light = '255 255 255 400' })))
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'zn_world_profile'; world_profile = 'preview'; origin = '0 0 16' })))
$vmf = "world`r`n{`r`n `"id`" `"1`"`r`n `"classname`" `"worldspawn`"`r`n `"skyname`" `"sky_day01_01`"`r`n$($brushes -join "`r`n")`r`n}`r`n$($entities -join "`r`n")"
$utf8 = [Text.UTF8Encoding]::new($false)
$src = Join-Path $output 'src'
$prefabs = Join-Path $output 'prefabs'
[IO.Directory]::CreateDirectory($src) | Out-Null
[IO.Directory]::CreateDirectory($prefabs) | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'zn_dev_prefab_anchor.vmf'), $vmf, $utf8)
[IO.File]::WriteAllText((Join-Path $src 'required.txt'), "zn_dev_prefab_anchor.vmf`r`n", $utf8)
[IO.File]::WriteAllText((Join-Path $src 'plan.json'), '{"schemaVersion":2,"safeZoneMaps":[]}', $utf8)
foreach ($document in $documents) {
    [IO.File]::WriteAllText((Join-Path $prefabs ($document.id + '.json')),
        (ConvertTo-Json -InputObject $document -Depth 10), $utf8)
}
Write-Output "Prepared two temporary set pieces and an isolated north-south road fixture at $output. No maps compiled or staged."
