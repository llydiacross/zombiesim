param(
    [string[]]$Profile = @('city', 'preview'),
    [switch]$AllProfiles,
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
            Where-Object { $generatorSettings.worldGeneration.profiles[$_].ContainsKey('thumbnail') } |
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

New-Item -ItemType Directory -Path $thumbnailDirectory -Force | Out-Null
foreach ($requestedProfile in $Profile) {
    $profileName = $requestedProfile.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        throw 'Specify a non-empty launcher thumbnail profile name.'
    }

    $worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $profileName -SettingsPath $SettingsPath
    $thumbnailProfile = $worldGenerationProfile.Config.thumbnail
    if ($null -eq $thumbnailProfile) {
        throw "World-generation profile '$profileName' does not define a thumbnail."
    }
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
}

Get-Item $outputPaths |
    Select-Object Name, Length, LastWriteTime