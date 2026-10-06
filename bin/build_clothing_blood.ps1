Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_blood.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'sign_assets.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$null = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$gameRoot = (Resolve-Path (Join-Path $root '..\..\..')).Path
$art = Join-Path $root 'assets\clothing'
$settings = Get-Content (Join-Path $art 'blood.json') -Raw | ConvertFrom-Json
$definition = Get-Content (Join-Path $art 'prototype.json') -Raw | ConvertFrom-Json
& (Join-Path $PSScriptRoot 'inspect_clothing_models.ps1') -UvGuideModels @('models/player/group01/male_03.mdl', 'models/player/group01/female_01.mdl')
$output = Join-Path $root 'generated\clothing_preview\blood'
$source = Join-Path $output 'source'
$game = Join-Path $output 'game'
$materials = Join-Path $game 'materials\models\zombiesim\clothing'
$null = New-Item -ItemType Directory -Force -Path $source, $materials
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'), '"GameInfo" { game "ZombieSim original blood layers" FileSystem { SteamAppId 4000 SearchPaths { game |gameinfo_path|. } } }', $utf8)
foreach ($variant in @(@('shirt', 'male'), @('shirt', 'female'), @('pants', 'male'))) {
    $garment, $sex = $variant
    $name = 'prototype_blood_' + $garment + $(if ($garment -eq 'shirt') { '_' + $sex } else { '' })
    $png = Join-Path $source "$name.png"
    $image = New-ClothingBloodLayer $settings $definition $garment $sex
    try { $image.Save($png, [Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    $tga = Join-Path $source "$name.tga"
    [ZombieSim.SignAssets.Builder]::WriteTga($png, $tga, 1024, 1024, $true)
    [IO.File]::WriteAllText((Join-Path $source "$name.txt"), "nolod 1`r`n", $utf8)
    $vtf = Join-Path $materials "$name.vtf"
    if (Test-Path -LiteralPath $vtf) { Remove-Item -LiteralPath $vtf }
    Invoke-SignCompiler (Join-Path $gameRoot 'bin\vtex.exe') ('-nop4 -nopause -game "{0}" -outdir "{1}" "{2}"' -f $game, $materials, $tga) (Join-Path $output "vtex_$name.log")
    if (-not (Test-Path -LiteralPath $vtf)) { throw "Missing compiled blood layer: $name" }
    [IO.File]::WriteAllText((Join-Path $materials "$name.vmt"), @"
"UnlitGeneric"
{
    "`$basetexture" "models/zombiesim/clothing/$name"
    "`$translucent" "1"
    "`$vertexcolor" "1"
    "`$vertexalpha" "1"
}
"@, $utf8)
    foreach ($directory in (Join-Path $root 'content\materials\models\zombiesim\clothing'),
        (Join-Path $gameRoot 'garrysmod\materials\models\zombiesim\clothing')) {
        $null = New-Item -ItemType Directory -Force -Path $directory
        foreach ($extension in 'vtf', 'vmt') {
            $file = Join-Path $materials "$name.$extension"
            $destination = Join-Path $directory "$name.$extension"
            Copy-Item -LiteralPath $file -Destination $destination -Force
            if ((Get-FileHash $file).Hash -ne (Get-FileHash $destination).Hash) { throw "Blood staging mismatch: $destination" }
        }
    }
}
Write-Host 'Built three original blood overlays / six staged files. Catalogue identities and runtime target budget unchanged.'
