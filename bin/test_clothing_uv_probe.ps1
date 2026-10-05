Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$gameDirectory = Split-Path -Parent (Split-Path -Parent $root)
$output = Join-Path $root 'generated\clothing_preview\uv_probe'
$definition = Get-Content -LiteralPath (Join-Path $root 'assets\clothing\uv_probe.json') -Raw | ConvertFrom-Json
$cases = [System.Collections.Generic.List[object]]::new()
function Assert-ClothingUv([string]$Name, [bool]$Passed) {
    $cases.Add([pscustomobject]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Clothing UV probe regression failed: $Name" }
    Write-Host "PASS: $Name"
}
try {
    $png = [System.Drawing.Bitmap]::new((Join-Path $output 'source\uv_probe.png'))
    try {
        Assert-ClothingUv 'original atlas is 1024x1024' ($png.Width -eq 1024 -and $png.Height -eq 1024)
        for ($row = 0; $row -lt 8; $row++) {
            for ($column = 0; $column -lt 8; $column++) {
                $pixel = $png.GetPixel($column * 128 + 16, $row * 128 + 80)
                $color = [System.Drawing.ColorTranslator]::FromHtml($definition.hues[$column])
                $factor = 1.0 - $row * 0.06
                Assert-ClothingUv "cell $([char](65 + $row))$($column + 1) has the exact opaque row/column colour" (
                    $pixel.A -eq 255 -and $pixel.R -eq [int]($color.R * $factor) -and
                    $pixel.G -eq [int]($color.G * $factor) -and $pixel.B -eq [int]($color.B * $factor))
                Assert-ClothingUv "cell $([char](65 + $row))$($column + 1) has a visible label/grid" (
                    $png.GetPixel($column * 128 + 1, $row * 128 + 64).R -eq 0 -and
                    $png.GetPixel($column * 128 + 1, $row * 128 + 64).G -eq 0)
            }
        }
    } finally { $png.Dispose() }
    $materialDirectory = Join-Path $root 'content\materials\models\zombiesim\clothing'
    $vtf = [System.IO.File]::ReadAllBytes((Join-Path $materialDirectory 'uv_probe.vtf'))
    Assert-ClothingUv 'compiled UV atlas has valid VTF signature/dimensions' (
        [System.Text.Encoding]::ASCII.GetString($vtf, 0, 4) -eq "VTF`0" -and
        [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024)
    $vmt = Get-Content -LiteralPath (Join-Path $materialDirectory 'uv_probe.vmt') -Raw
    Assert-ClothingUv 'scene-lit diagnostic material uses only original atlas and no player-colour tint' (
        $vmt.Contains('"VertexLitGeneric"') -and $vmt.Contains('"$basetexture" "models/zombiesim/clothing/uv_probe"') -and
        $vmt -notmatch 'PlayerColor|selfillum|models/humans')
    foreach ($extension in 'vtf', 'vmt') {
        $source = Join-Path $output "game\materials\models\zombiesim\clothing\uv_probe.$extension"
        $hash = (Get-FileHash -LiteralPath $source).Hash
        foreach ($directory in $materialDirectory, (Join-Path $gameDirectory 'materials\models\zombiesim\clothing')) {
            Assert-ClothingUv "$extension staging matches generated original asset in $directory" (
                (Get-FileHash -LiteralPath (Join-Path $directory "uv_probe.$extension")).Hash -eq $hash)
        }
    }
} finally {
    [pscustomobject]@{ cases = $cases.ToArray(); passed = @($cases | Where-Object passed).Count } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'test-report.json') -Encoding UTF8
}
Write-Host "Clothing UV probe checks passed: $($cases.Count)/$($cases.Count)."
