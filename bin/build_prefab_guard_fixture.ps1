param([Parameter(Mandatory = $true)][string]$OutputDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Fixture output already exists; choose a fresh directory: $output" }

$shirt = 'catalogue_fabric_shirt_blue_plain'
$pants = 'catalogue_fabric_pants_black_plain'
$catalogue = Get-Content -LiteralPath (Join-Path $root 'content\data_static\clothing_catalogue.json') -Raw | ConvertFrom-Json
foreach ($selection in @(@{ id = $shirt; garment = 'shirt' }, @{ id = $pants; garment = 'pants' })) {
    $finish = $catalogue.finishes.PSObject.Properties[$selection.id]
    if ($null -eq $finish -or $finish.Value.garment -cne $selection.garment) {
        throw "The guard fixture clothing finish is unavailable: $($selection.id)"
    }
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
$brushes = @(
    (New-ZooBox -1024 -640 -32 1024 640 0),
    (New-ZooBox -1024 -640 512 1024 640 544),
    (New-ZooBox -1056 -640 -32 -1024 640 544),
    (New-ZooBox 1024 -640 -32 1056 640 544),
    (New-ZooBox -1056 -640 -32 1056 -608 544),
    (New-ZooBox -1056 608 -32 1056 640 544)
)
$entities = @(
    (New-ZooEntity ([ordered]@{
        classname = 'zn_prefab_guard'; targetname = 'hammer_default_guard'
        origin = '-200 0 0'; angles = '0 270 0'
    })),
    (New-ZooEntity ([ordered]@{
        classname = 'zn_prefab_guard'; targetname = 'hammer_override_guard'
        guard_name = 'Hammer fixture'; model = 'models/player/group01/male_03.mdl'
        idle = 'idle_all_01'; weapon = 'smg'; range = '1200'; shirt = $shirt; pants = $pants
        damage = '25'; fire_interval = '0.075'; spread = '0.04'
        origin = '200 0 0'; angles = '0 270 0'
    })),
    (New-ZooEntity ([ordered]@{ classname = 'info_player_start'; origin = '0 -320 16'; angles = '0 90 0' })),
    (New-ZooEntity ([ordered]@{ classname = 'light'; origin = '0 0 400'; _light = '255 255 255 400' })),
    (New-ZooEntity ([ordered]@{ classname = 'zn_world_profile'; world_profile = 'preview'; origin = '0 0 16' }))
)
$vmf = "world`r`n{`r`n `"id`" `"1`"`r`n `"classname`" `"worldspawn`"`r`n `"skyname`" `"sky_day01_01`"`r`n$($brushes -join "`r`n")`r`n}`r`n$($entities -join "`r`n")"
$src = Join-Path $output 'src'
[IO.Directory]::CreateDirectory($src) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $src 'zn_dev_prefab_anchor.vmf'), $vmf, $utf8)
Write-Output "Prepared a two-guard isolated Hammer fixture at $output. No maps compiled or staged."
