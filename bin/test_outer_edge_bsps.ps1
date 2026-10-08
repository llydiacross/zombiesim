param([string]$OutputRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'generated\outer_edges' }
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1') -Force
$checked = 0
foreach ($filename in Get-Content -LiteralPath (Join-Path $OutputRoot 'coverage-required.txt')) {
    $layout = Get-Content -Raw -LiteralPath (Join-Path $OutputRoot ('coverage\' + [IO.Path]::ChangeExtension($filename, '.layout.json'))) | ConvertFrom-Json
    $bspPath = Join-Path $OutputRoot ('coverage-build\' + [IO.Path]::ChangeExtension($filename, '.bsp'))
    $bytes = [IO.File]::ReadAllBytes($bspPath)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'VBSP') { throw "Invalid fixture BSP: $bspPath" }
    $offset = [BitConverter]::ToInt32($bytes, 8)
    $length = [BitConverter]::ToInt32($bytes, 12)
    if ($offset -lt 0 -or $length -lt 1 -or [long]$offset + $length -gt $bytes.Length) { throw "Invalid BSP entity lump: $bspPath" }
    $entities = [ZombieSim.Skybox.KeyValuesParser]::Parse([Text.Encoding]::ASCII.GetString($bytes, $offset, $length).TrimEnd([char]0)).Children
    foreach ($placement in $layout.outerPlacements) {
        $source = [ZombieSim.Skybox.KeyValuesParser]::Parse((Get-Content -Raw -LiteralPath (Join-Path $projectRoot ('tiletemplates\' + $placement.template))))
        foreach ($prop in $source.Children | Where-Object { $_.Get('classname') -eq 'prop_dynamic_override' }) {
            $local = [ZombieSim.Skybox.Vec3]::Parse($prop.Get('origin'))
            $angle = [double]$placement.rotationYaw * [Math]::PI / 180
            $x = ([int]$placement.tileX - 2) * 640 + $local.X * [Math]::Cos($angle) - $local.Y * [Math]::Sin($angle)
            $y = (2 - [int]$placement.tileY) * 640 + $local.X * [Math]::Sin($angle) + $local.Y * [Math]::Cos($angle)
            $matches = @($entities | Where-Object {
                if ($_.Get('model') -ne $prop.Get('model') -or $_.Get('classname') -ne 'prop_dynamic_override') { return $false }
                $actual = [ZombieSim.Skybox.Vec3]::Parse($_.Get('origin'))
                return [Math]::Abs($actual.X - $x) -lt 0.01 -and [Math]::Abs($actual.Y - $y) -lt 0.01 -and [Math]::Abs($actual.Z - $local.Z) -lt 0.01
            })
            if ($matches.Count -ne 1) { throw "Corrected edge prop absent/duplicated in $filename at $x,$y,$($local.Z): $($prop.Get('model'))" }
            $checked++
        }
    }
}
if ($checked -eq 0) { throw 'No corrected edge props were exercised by the compiled fixtures.' }
Write-Output "Outer-edge BSP entity checks: $checked fixed dynamic prop instances retained at their exact transformed positions."
