param([string]$SettingsPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-GeneratorSettingsHashtable {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) {
            $result[$key] = ConvertTo-GeneratorSettingsHashtable $Value[$key]
        }
        return $result
    }
    if ($Value.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject') {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-GeneratorSettingsHashtable $property.Value
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { ConvertTo-GeneratorSettingsHashtable $_ })
    }
    return $Value
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
    $SettingsPath = Join-Path $projectRoot 'generator-settings.json'
}
if (-not (Test-Path $SettingsPath)) {
    throw "Generator settings file was not found: $SettingsPath"
}

$settings = ConvertTo-GeneratorSettingsHashtable (Get-Content -Raw $SettingsPath | ConvertFrom-Json)
if ($settings.schemaVersion -notin @(1, 2)) {
    throw "Unsupported generator settings schema version '$($settings.schemaVersion)'. Expected 1 or 2."
}
foreach ($requiredSection in @('paths', 'directions', 'mapGeneration', 'cellPlanning', 'vmfBuild')) {
    if (-not $settings.ContainsKey($requiredSection)) {
        throw "Generator settings are missing required section '$requiredSection': $SettingsPath"
    }
}

Write-Output -NoEnumerate $settings