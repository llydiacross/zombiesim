Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_blood.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$settings = Get-Content (Join-Path $root 'assets\clothing\blood.json') -Raw | ConvertFrom-Json
$definition = Get-Content (Join-Path $root 'assets\clothing\prototype.json') -Raw | ConvertFrom-Json
$output = Join-Path $root 'generated\clothing_preview\blood'
$passed = 0
function Assert-Blood([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Clothing blood regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Get-ImageHash([Drawing.Bitmap]$Image) {
    $data = $Image.LockBits([Drawing.Rectangle]::new(0, 0, $Image.Width, $Image.Height),
        [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [byte[]]::new($data.Stride * $data.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        return [BitConverter]::ToString($sha.ComputeHash($bytes))
    } finally { $Image.UnlockBits($data); $sha.Dispose() }
}
foreach ($variant in @(@('shirt', 'male'), @('shirt', 'female'), @('pants', 'male'))) {
    $garment, $sex = $variant
    $name = 'prototype_blood_' + $garment + $(if ($garment -eq 'shirt') { '_' + $sex } else { '' })
    $image = [Drawing.Bitmap]::new((Join-Path $output "source\$name.png"))
    $expected = New-ClothingBloodLayer $settings $definition $garment $sex
    $maskName = if ($garment -eq 'shirt') { "prototype_shirt_$sex" } else { 'prototype_pants' }
    $mask = [Drawing.Bitmap]::new((Join-Path $root "generated\clothing_preview\prototype\source\$maskName.png"))
    try {
        Assert-Blood "$name deterministic original pixels match current source" ((Get-ImageHash $image) -eq (Get-ImageHash $expected))
        $outside = 0; $visible = 0; $translucent = 0; $clear = 0
        for ($y = 0; $y -lt 1024; $y++) {
            for ($x = 0; $x -lt 1024; $x++) {
                $pixel = $image.GetPixel($x, $y)
                if ($pixel.A -eq 0) { $clear++; continue }
                $visible++
                if ($pixel.A -lt 255) { $translucent++ }
                if ($mask.GetPixel($x, $y).A -eq 0) { $outside++ }
            }
        }
        Assert-Blood "$name all1048576pixels preserve garment mask/skin/shoes/inner shirt" ($outside -eq 0)
        Assert-Blood "$name has bounded partial coverage rather than replacing the finish" (
            $visible -gt 5000 -and $visible -lt 300000 -and $clear -gt 700000)
        Assert-Blood "$name retains soft partial-alpha stains" ($translucent -gt $visible * 0.9)
    } finally { $image.Dispose(); $expected.Dispose(); $mask.Dispose() }
    $vtf = [IO.File]::ReadAllBytes((Join-Path $output "game\materials\models\zombiesim\clothing\$name.vtf"))
    Assert-Blood "$name compiled1024square alpha/DXT5/11mips" (
        [Text.Encoding]::ASCII.GetString($vtf, 0, 4) -eq "VTF`0" -and
        [BitConverter]::ToUInt16($vtf, 16) -eq 1024 -and [BitConverter]::ToUInt16($vtf, 18) -eq 1024 -and
        [BitConverter]::ToInt32($vtf, 52) -eq 15 -and $vtf[56] -eq 11 -and
        ([BitConverter]::ToUInt32($vtf, 20) -band 12288) -ne 0)
    foreach ($extension in 'vtf', 'vmt') {
        $file = Join-Path $output "game\materials\models\zombiesim\clothing\$name.$extension"
        foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
            (Join-Path $root '..\..\materials\models\zombiesim\clothing')) {
            Assert-Blood "$name.$extension exact staged hash $directory" (
                (Get-FileHash -LiteralPath $file).Hash -eq (Get-FileHash -LiteralPath (Join-Path $directory "$name.$extension")).Hash)
        }
    }
}
foreach ($property in 'patches', 'droplets', 'seed', 'maximumAlpha') {
    $invalid = $settings | ConvertTo-Json | ConvertFrom-Json
    $invalid.$property = -1
    $failed = $false
    try { $image = New-ClothingBloodLayer $invalid $definition pants; $image.Dispose() }
    catch {
        if ($_.Exception.Message -notlike "Invalid clothing blood setting: $property") { throw }
        $failed = $true
    }
    Assert-Blood "$property invalid input fails explicitly" $failed
}
$female = New-ClothingBloodLayer $settings $definition pants female
$male = New-ClothingBloodLayer $settings $definition pants male
try { Assert-Blood 'pants legitimately share the existing verified common garment mask' ((Get-ImageHash $male) -eq (Get-ImageHash $female)) }
finally { $female.Dispose(); $male.Dispose() }
Write-Host "Clothing blood checks passed: $passed/$passed."
