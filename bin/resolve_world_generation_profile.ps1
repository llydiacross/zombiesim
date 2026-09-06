param(
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LegacyProfileValue {
    param(
        [hashtable]$Settings,
        [string]$Key,
        [string]$Fallback
    )

    if ($Settings.paths.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Settings.paths[$Key])) {
        return [string]$Settings.paths[$Key]
    }
    return $Fallback
}

function New-LegacyWorldGenerationProfiles {
    param([hashtable]$Settings)

    $profiles = @{
        city = @{
            filePrefix = 'map'
            gridCells = [int]$Settings.mapGeneration.gridCells
            exportLayers = $false
            cellDirectory = Get-LegacyProfileValue $Settings 'cellDirectory' 'generated/src'
            buildDirectory = Get-LegacyProfileValue $Settings 'buildDirectory' 'generated/build'
            releaseMapDirectory = Get-LegacyProfileValue $Settings 'releaseMapDirectory' 'content/maps/city'
            runtimeWorldData = Get-LegacyProfileValue $Settings 'runtimeWorldData' 'content/data_static/zombiesim_world.json'
        }
        preview = @{
            filePrefix = 'preview'
            gridCells = [int]$Settings.mapGeneration.previewGridCells
            exportLayers = [bool]$Settings.mapGeneration.rendering.previewExportsLayers
            cellDirectory = Get-LegacyProfileValue $Settings 'previewCellDirectory' 'generated/src_preview'
            buildDirectory = Get-LegacyProfileValue $Settings 'previewBuildDirectory' 'generated/build_preview'
            releaseMapDirectory = Get-LegacyProfileValue $Settings 'previewReleaseMapDirectory' 'content/maps/preview'
            runtimeWorldData = Get-LegacyProfileValue $Settings 'previewRuntimeWorldData' 'content/data_static/zombiesim_world_preview.json'
        }
    }

    if ($Settings.ContainsKey('launcherThumbnails') -and $Settings.launcherThumbnails.ContainsKey('profiles')) {
        foreach ($profileName in $profiles.Keys) {
            if ($Settings.launcherThumbnails.profiles.ContainsKey($profileName)) {
                $profiles[$profileName].thumbnail = $Settings.launcherThumbnails.profiles[$profileName]
            }
        }
    }

    return $profiles
}

function Copy-GeneratorSettingValue {
    param([object]$Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $Value.Keys) {
            $copy[$key] = Copy-GeneratorSettingValue $Value[$key]
        }
        Write-Output -NoEnumerate $copy
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $copy = @($Value | ForEach-Object { Copy-GeneratorSettingValue $_ })
        Write-Output -NoEnumerate ([object[]]$copy)
        return
    }

    Write-Output -NoEnumerate $Value
}

function Merge-GeneratorSettingValues {
    param(
        [object]$BaseValue,
        [object]$OverrideValue
    )

    if ($BaseValue -is [System.Collections.IDictionary] -and $OverrideValue -is [System.Collections.IDictionary]) {
        $merged = Copy-GeneratorSettingValue $BaseValue
        foreach ($key in $OverrideValue.Keys) {
            if ($merged.ContainsKey($key)) {
                $merged[$key] = Merge-GeneratorSettingValues $merged[$key] $OverrideValue[$key]
            } else {
                $merged[$key] = Copy-GeneratorSettingValue $OverrideValue[$key]
            }
        }
        Write-Output -NoEnumerate $merged
        return
    }

    Copy-GeneratorSettingValue $OverrideValue
}

$generatorSettings = & (Join-Path $PSScriptRoot 'import_generator_settings.ps1') -SettingsPath $SettingsPath
$profiles = $null
$defaultProfile = 'city'
if ($generatorSettings.ContainsKey('worldGeneration') -and $generatorSettings.worldGeneration.ContainsKey('profiles')) {
    $profiles = $generatorSettings.worldGeneration.profiles
    if ($generatorSettings.worldGeneration.ContainsKey('defaultProfile')) {
        $defaultProfile = [string]$generatorSettings.worldGeneration.defaultProfile
    }
} else {
    $profiles = New-LegacyWorldGenerationProfiles $generatorSettings
}

if ($Preview) {
    if (-not [string]::IsNullOrWhiteSpace($WorldProfile) -and $WorldProfile -notmatch '^(?i:preview)$') {
        throw 'Use either -Preview or -WorldProfile with a profile other than preview, not both.'
    }
    $WorldProfile = 'preview'
}
if ([string]::IsNullOrWhiteSpace($WorldProfile)) {
    $WorldProfile = $defaultProfile
}

$WorldProfile = $WorldProfile.Trim().ToLowerInvariant()
if ($WorldProfile -notmatch '^[a-z0-9_-]+$' -or -not $profiles.ContainsKey($WorldProfile)) {
    throw "Unknown world-generation profile '$WorldProfile'. Add it under worldGeneration.profiles in generator-settings.json."
}

$profileSettings = $profiles[$WorldProfile]
foreach ($requiredPath in @('filePrefix', 'cellDirectory', 'buildDirectory', 'releaseMapDirectory', 'runtimeWorldData')) {
    if (-not $profileSettings.ContainsKey($requiredPath) -or [string]::IsNullOrWhiteSpace([string]$profileSettings[$requiredPath])) {
        throw "World-generation profile '$WorldProfile' must define a non-empty '$requiredPath' value."
    }
}
if (-not $profileSettings.ContainsKey('gridCells') -or [int]$profileSettings.gridCells -lt 1) {
    throw "World-generation profile '$WorldProfile' must define gridCells greater than zero."
}
if (-not $profileSettings.ContainsKey('exportLayers')) {
    throw "World-generation profile '$WorldProfile' must define exportLayers."
}

$effectiveSettings = $generatorSettings
if ($profileSettings.ContainsKey('overrides')) {
    $overrides = $profileSettings.overrides
    if (-not ($overrides -is [System.Collections.IDictionary])) {
        throw "World-generation profile '$WorldProfile' overrides must be an object."
    }
    foreach ($reservedSection in @('schemaVersion', 'worldGeneration')) {
        if ($overrides.ContainsKey($reservedSection)) {
            throw "World-generation profile '$WorldProfile' cannot override '$reservedSection'."
        }
    }
    $effectiveSettings = Merge-GeneratorSettingValues $generatorSettings $overrides
}

[pscustomobject]@{
    Name = $WorldProfile
    Settings = $effectiveSettings
    Config = $profileSettings
}