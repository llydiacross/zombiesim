param([Parameter(Mandatory = $true)][string]$OutputDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Fixture output already exists; choose a fresh directory: $output" }
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
$entities = [Collections.Generic.List[string]]::new()
foreach ($anchor in @(
    @{ x = -400; y = 200; yaw = 0 },
    @{ x = 400; y = 200; yaw = 90 },
    @{ x = -400; y = -200; yaw = 180 },
    @{ x = 400; y = -200; yaw = 270 }
)) {
    $entities.Add((New-ZooEntity ([ordered]@{
        classname = 'zn_prefab_anchor'; targetname = "guard_anchor_$($anchor.yaw)"
        prefab_tags = 'guardFixture'; origin = "$($anchor.x) $($anchor.y) 0"; angles = "0 $($anchor.yaw) 0"
    })))
}
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'info_player_start'; origin = '0 -450 16'; angles = '0 90 0' })))
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'light'; origin = '0 0 400'; _light = '255 255 255 400' })))
$entities.Add((New-ZooEntity ([ordered]@{ classname = 'zn_world_profile'; world_profile = 'preview'; origin = '0 0 16' })))
$vmf = "world`r`n{`r`n `"id`" `"1`"`r`n `"classname`" `"worldspawn`"`r`n `"skyname`" `"sky_day01_01`"`r`n$($brushes -join "`r`n")`r`n}`r`n$($entities -join "`r`n")"
$src = Join-Path $output 'src'
[IO.Directory]::CreateDirectory($src) | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'zn_dev_prefab_anchor.vmf'), $vmf, [Text.UTF8Encoding]::new($false))
Write-Output "Prepared a four-anchor guard prefab fixture at $output. No maps compiled or staged."
