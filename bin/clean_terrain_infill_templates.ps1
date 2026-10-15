param(
    [Parameter(Mandatory)][string[]]$LayoutDirectories,
    [string]$WorldProfile = 'preview',
    [string]$SettingsPath = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'terrain_infill.psm1')
$root = Split-Path -Parent $PSScriptRoot
$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -SettingsPath $SettingsPath
$templates = Join-Path $root $profile.Settings.paths.templateDirectory
$directory = Join-Path $templates 'terrain\infill'
$baseText = [IO.File]::ReadAllText((Join-Path $templates 'terrain\tile_grass.vmf'))
$used = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @('tile_ground_full.vmf', 'tile_ground_half.vmf', 'tile_ground_quarter.vmf')) { [void]$used.Add($name) }
$layouts = @()
foreach ($layoutDirectory in $LayoutDirectories) {
    $files = @(Get-ChildItem -LiteralPath $layoutDirectory -Filter '*.layout.json' -File)
    if ($files.Count -eq 0) { throw "Cleanup requires current generated layouts: $layoutDirectory" }
    foreach ($file in $files) {
        $layout = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        $vmf = $file.FullName.Substring(0, $file.FullName.Length - '.layout.json'.Length) + '.vmf'
        if ($layout.vmfSha256 -cne (Get-FileHash -LiteralPath $vmf -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Stale cleanup layout: $($file.FullName)" }
        $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($vmf))
        foreach ($instance in $tree.Children | Where-Object { $_.Name -eq 'entity' -and $_.Get('classname') -eq 'func_instance' }) {
            $source = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $vmf) $instance.Get('file').Replace('/', '\')))
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing current preview dependency: $source" }
            if ([IO.Path]::GetDirectoryName($source) -eq $directory) { [void]$used.Add([IO.Path]::GetFileName($source)) }
        }
        $layouts += $file.FullName
    }
}
# Authored nested instances are independent of the selected current preview set.
foreach ($source in Get-ChildItem -LiteralPath $templates -Filter '*.vmf' -File -Recurse) {
    if ($source.DirectoryName -eq $directory) { continue }
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($source.FullName), '"file"\s+"([^"]+\.vmf)"', 'IgnoreCase')) {
        $path = [IO.Path]::GetFullPath((Join-Path $source.DirectoryName $match.Groups[1].Value.Replace('/', '\')))
        if ([IO.Path]::GetDirectoryName($path) -eq $directory) { [void]$used.Add([IO.Path]::GetFileName($path)) }
    }
}
$archiveRoot = Join-Path $root 'generated\retired_terrain_infill'
$report = [Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.vmf' -File) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $status = 'preserved_unknown_or_artist_edited'
    $destination = $null
    if ($used.Contains($file.Name)) { $status = 'used' }
    elseif (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($file.FullName, '.vmx'))) { $status = 'preserved_companion_owned' }
    else {
        $text = [IO.File]::ReadAllText($file.FullName)
        $expected = $null
        if ($file.Name -match '^tile_ground_patch_u([0-9p]+)_u([0-9p]+)\.vmf$') {
            $width = [double]::Parse($Matches[1].Replace('p', '.'), [Globalization.CultureInfo]::InvariantCulture)
            $height = [double]::Parse($Matches[2].Replace('p', '.'), [Globalization.CultureInfo]::InvariantCulture)
            $expected = New-ZMInfillRectangleVmf $baseText $width $height
        } elseif ($file.Name -match '^tile_ground_shape_[0-9a-f]{64}\.vmf$') {
            $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse($text)
            $solid = $tree.Child('world').Child('solid')
            if ($null -ne $solid) {
                $points = @($solid.Children | Where-Object Name -eq side | ForEach-Object { $_.Child('vertices_plus') } | Where-Object { $null -ne $_ } |
                    ForEach-Object { $_.GetAll('v') } | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_) } |
                    ForEach-Object { [ZombieSim.Infill.Point]::new($_.X, $_.Y) })
                $polygon = [ZombieSim.Infill.Geometry]::Hull([ZombieSim.Infill.Point[]]$points)
                if ($polygon.Count -ge 3) {
                    $expected = New-ZMInfillShapeVmf $baseText $polygon
                    if ($expected -cne $text) {
                        $legacy = New-ZMInfillShapeVmf $baseText $polygon -LegacyWinding
                        if ($legacy -ceq $text) { $expected = $legacy }
                    }
                }
            }
        }
        if ($null -ne $expected -and $expected -ceq $text) {
            $status = 'unused_unmodified_default'
            $destination = Join-Path (Join-Path $archiveRoot $hash) $file.Name
            if ($Apply) {
                [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
                if (-not (Test-Path -LiteralPath $destination)) { [IO.File]::Copy($file.FullName, $destination) }
                if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $hash) { throw "Retired source archive hash mismatch: $destination" }
                Remove-Item -LiteralPath $file.FullName
                $status = 'archived_unused_default'
            }
        }
    }
    $report.Add([pscustomobject]@{ source = $file.FullName; sha256 = $hash; status = $status; archive = $destination })
}
if ($Apply) {
    [IO.Directory]::CreateDirectory($archiveRoot) | Out-Null
    $run = [ordered]@{ layouts = $layouts; sources = $report.ToArray(); historicalPreviewLimit = 'Superseded generated fixtures may refer to retired sources. Restore their exact archived sources or regenerate from current inputs before use.' }
    $reportPath = Join-Path $archiveRoot ('cleanup-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff') + '.json')
    [IO.File]::WriteAllText($reportPath, ($run | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
$report.ToArray()
