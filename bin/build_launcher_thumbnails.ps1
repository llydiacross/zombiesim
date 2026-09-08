param(
    [string[]]$Profile = @('city', 'preview'),
    [switch]$AllProfiles,
    [switch]$CellThumbnails,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-MapThumbnail {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [Parameter(Mandatory)]
        [string]$Title,
        [bool]$ShowLogo
    )

    $source = $null
    $bitmap = $null
    $graphics = $null
    $logo = $null
    $titleFont = $null
    $stringFormat = $null
    $overlayBrush = $null
    $footerBrush = $null
    $accentBrush = $null

    try {
        $source = [System.Drawing.Image]::FromFile($SourcePath)
        $bitmap = [System.Drawing.Bitmap]::new(512, 512)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::FromArgb(14, 18, 24))

        $scale = [Math]::Max(512 / $source.Width, 512 / $source.Height)
        $drawWidth = [int][Math]::Ceiling($source.Width * $scale)
        $drawHeight = [int][Math]::Ceiling($source.Height * $scale)
        $drawX = [int]((512 - $drawWidth) / 2)
        $drawY = [int]((512 - $drawHeight) / 2)
        $graphics.DrawImage($source, $drawX, $drawY, $drawWidth, $drawHeight)

        $overlayBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(70, 0, 0, 0))
        $graphics.FillRectangle($overlayBrush, 0, 0, 512, 512)

        if ($ShowLogo) {
            $logoPath = Join-Path $projectRoot 'logo.png'
            $logo = [System.Drawing.Image]::FromFile($logoPath)
            $graphics.DrawImage($logo, 56, 180, 400, 85)
        }

        $footerBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(210, 10, 16, 22))
        $graphics.FillRectangle($footerBrush, 0, 418, 512, 94)

        $accentColor = if ($ShowLogo) {
            [System.Drawing.Color]::FromArgb(231, 60, 62)
        } else {
            [System.Drawing.Color]::FromArgb(87, 190, 148)
        }
        $accentBrush = [System.Drawing.SolidBrush]::new($accentColor)
        $graphics.FillRectangle($accentBrush, 0, 418, 512, 8)

        $titleFont = [System.Drawing.Font]::new('Bahnschrift', 30, [System.Drawing.FontStyle]::Bold)
        $stringFormat = [System.Drawing.StringFormat]::new()
        $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        $graphics.DrawString($Title, $titleFont, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new(0, 424, 512, 82), $stringFormat)

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($accentBrush) { $accentBrush.Dispose() }
        if ($footerBrush) { $footerBrush.Dispose() }
        if ($overlayBrush) { $overlayBrush.Dispose() }
        if ($stringFormat) { $stringFormat.Dispose() }
        if ($titleFont) { $titleFont.Dispose() }
        if ($logo) { $logo.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($source) { $source.Dispose() }
    }
}

function New-CellMapThumbnail {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $source = $null
    $bitmap = $null
    $graphics = $null

    try {
        $source = [System.Drawing.Image]::FromFile($SourcePath)
        if ($source.Width -ne $source.Height) {
            throw "Cell map thumbnail source must be square: $SourcePath"
        }

        $bitmap = [System.Drawing.Bitmap]::new(512, 512)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($source, 0, 0, 512, 512)
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($source) { $source.Dispose() }
    }
}

function Get-ThumbnailProfileValue {
    param(
        [hashtable]$ThumbnailProfile,
        [string]$ProfileName,
        [string]$PropertyName
    )

    if (-not $ThumbnailProfile.ContainsKey($PropertyName) -or [string]::IsNullOrWhiteSpace([string]$ThumbnailProfile[$PropertyName])) {
        throw "Launcher thumbnail profile '$ProfileName' must define a non-empty '$PropertyName' value."
    }

    return [string]$ThumbnailProfile[$PropertyName]
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath
if ($AllProfiles) {
    if ($PSBoundParameters.ContainsKey('Profile')) {
        throw 'Use either -Profile or -AllProfiles, not both.'
    }
    if ($generatorSettings.ContainsKey('worldGeneration') -and $generatorSettings.worldGeneration.ContainsKey('profiles')) {
        $Profile = @($generatorSettings.worldGeneration.profiles.Keys |
            Where-Object { $CellThumbnails -or $generatorSettings.worldGeneration.profiles[$_].ContainsKey('thumbnail') } |
            Sort-Object)
    } else {
        $Profile = @('city', 'preview')
    }
}
if ($Profile.Count -eq 0) {
    throw 'Specify at least one launcher thumbnail profile with a thumbnail definition.'
}

$thumbnailDirectory = Join-Path $projectRoot 'content\maps\thumb'
$outputPaths = [System.Collections.Generic.List[string]]::new()
$targetMaps = @{}
$launcherThumbnailCount = 0
$cellThumbnailCount = 0

New-Item -ItemType Directory -Path $thumbnailDirectory -Force | Out-Null
foreach ($requestedProfile in $Profile) {
    $profileName = $requestedProfile.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        throw 'Specify a non-empty launcher thumbnail profile name.'
    }

    $worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $profileName -SettingsPath $SettingsPath
    $thumbnailProfile = $worldGenerationProfile.Config.thumbnail
    if ($null -eq $thumbnailProfile -and -not $CellThumbnails) {
        throw "World-generation profile '$profileName' does not define a thumbnail."
    }
    if ($null -ne $thumbnailProfile) {
        $mapName = Get-ThumbnailProfileValue -ThumbnailProfile $thumbnailProfile -ProfileName $profileName -PropertyName 'map'
        if ($mapName -notmatch '^[a-z0-9_-]+$') {
            throw "Launcher thumbnail profile '$profileName' has invalid map name '$mapName'."
        }
        if ($targetMaps.ContainsKey($mapName)) {
            throw "Launcher thumbnail profiles '$($targetMaps[$mapName])' and '$profileName' both target '$mapName'."
        }

        $sourcePath = Join-Path $projectRoot (Get-ThumbnailProfileValue -ThumbnailProfile $thumbnailProfile -ProfileName $profileName -PropertyName 'source')
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Launcher thumbnail profile '$profileName' source image was not found: $sourcePath"
        }

        $showLogo = [bool]$thumbnailProfile.showLogo
        if ($showLogo -and -not (Test-Path -LiteralPath (Join-Path $projectRoot 'logo.png') -PathType Leaf)) {
            throw "Launcher thumbnail profile '$profileName' requires logo.png."
        }

        $targetMaps[$mapName] = $profileName
        $outputPath = Join-Path $thumbnailDirectory "$mapName.png"
        New-MapThumbnail -SourcePath $sourcePath -OutputPath $outputPath -Title (Get-ThumbnailProfileValue -ThumbnailProfile $thumbnailProfile -ProfileName $profileName -PropertyName 'title') -ShowLogo $showLogo
        $outputPaths.Add($outputPath)
        $launcherThumbnailCount++
    }

    if ($CellThumbnails) {
        $cellMaterialDirectory = Join-Path $projectRoot (Join-Path (Join-Path 'content\materials\worlds' $worldGenerationProfile.Name) 'cells')
        if (-not (Test-Path -LiteralPath $cellMaterialDirectory -PathType Container)) {
            throw "Cell map materials for profile '$profileName' were not found: $cellMaterialDirectory. Run build_cell_map_materials.ps1 first."
        }

        $releaseMapDirectory = [string]$worldGenerationProfile.Config.releaseMapDirectory
        $mapSubdirectory = $releaseMapDirectory -replace '^[\\/]*content[\\/]+maps[\\/]*', ''
        if ([string]::IsNullOrWhiteSpace($mapSubdirectory) -or $mapSubdirectory -eq $releaseMapDirectory) {
            throw "World-generation profile '$profileName' must stage recipe maps below content/maps to generate GMod thumbnails."
        }
        $cellThumbnailDirectory = Join-Path $thumbnailDirectory $mapSubdirectory
        New-Item -ItemType Directory -Path $cellThumbnailDirectory -Force | Out-Null

        $cellMaterialPaths = @(Get-ChildItem -LiteralPath $cellMaterialDirectory -Filter '*.png' -File | Sort-Object Name)
        if ($cellMaterialPaths.Count -eq 0) {
            throw "Cell map materials for profile '$profileName' are empty: $cellMaterialDirectory"
        }
        foreach ($cellMaterialPath in $cellMaterialPaths) {
            $mapName = [System.IO.Path]::GetFileNameWithoutExtension($cellMaterialPath.Name)
            if ($mapName -notmatch '^[a-z0-9_+\-]+$') {
                throw "Cell map material '$($cellMaterialPath.Name)' has an invalid GMod map name."
            }
            $thumbnailKey = ((Join-Path $mapSubdirectory $mapName) -replace '\\', '/').ToLowerInvariant()
            if ($targetMaps.ContainsKey($thumbnailKey)) {
                throw "GMod thumbnail '$thumbnailKey' is produced by both '$($targetMaps[$thumbnailKey])' and '$profileName'."
            }

            $targetMaps[$thumbnailKey] = $profileName
            $outputPath = Join-Path $cellThumbnailDirectory "$mapName.png"
            New-CellMapThumbnail -SourcePath $cellMaterialPath.FullName -OutputPath $outputPath
            $outputPaths.Add($outputPath)
            $cellThumbnailCount++
        }
    }
}

if ($CellThumbnails) {
    Write-Output "Generated $launcherThumbnailCount launcher thumbnail(s) and $cellThumbnailCount recipe-map GMod thumbnail(s): $thumbnailDirectory"
} else {
    Get-Item $outputPaths |
        Select-Object Name, Length, LastWriteTime
}