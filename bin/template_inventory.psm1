Set-StrictMode -Version Latest

function Add-ZMExplicitTileTemplateReferences {
    param(
        [object]$Node,
        [string]$SettingPath,
        [System.Collections.Generic.List[object]]$References
    )

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            Add-ZMExplicitTileTemplateReferences $Node[$key] "$SettingPath.$key" $References
        }
        return
    }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $index = 0
        foreach ($value in $Node) {
            Add-ZMExplicitTileTemplateReferences $value "$SettingPath[$index]" $References
            $index++
        }
        return
    }
    if ($Node -is [string] -and $Node.EndsWith('.vmf', [StringComparison]::OrdinalIgnoreCase) -and $Node -notmatch '[*?]') {
        $References.Add([pscustomobject]@{
            setting = $SettingPath
            template = $Node
        }) | Out-Null
    }
}

function Assert-ZMRequiredMotorwayTemplateSettings {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Settings)

    if (-not $Settings.ContainsKey('cellPlanning') -or -not ($Settings.cellPlanning -is [System.Collections.IDictionary])) {
        throw 'Generator settings must define cellPlanning before motorway placement.'
    }
    $planner = $Settings.cellPlanning
    foreach ($key in @('motorway-straight', 'motorway-corner', 'motorway-tjunction', 'motorway-crossjunction', 'motorway-deadend')) {
        if (-not $planner.ContainsKey('topologyTemplates') -or
            -not ($planner.topologyTemplates -is [System.Collections.IDictionary]) -or
            -not $planner.topologyTemplates.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string]$planner.topologyTemplates[$key])) {
            throw "Required motorway topology template 'cellPlanning.topologyTemplates.$key' is missing."
        }
    }
    foreach ($key in @('bridge', 'onramp', 'onramp-dual')) {
        if (-not $planner.ContainsKey('transportTemplates') -or
            -not ($planner.transportTemplates -is [System.Collections.IDictionary]) -or
            -not $planner.transportTemplates.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string]$planner.transportTemplates[$key])) {
            throw "Required motorway transport template 'cellPlanning.transportTemplates.$key' is missing."
        }
    }
}

function Assert-ZMConfiguredTileTemplatePaths {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Settings,
        [Parameter(Mandatory = $true)][string]$TemplateRoot
    )

    $references = [System.Collections.Generic.List[object]]::new()
    if ($Settings.ContainsKey('cellPlanning') -and $Settings.cellPlanning -is [System.Collections.IDictionary]) {
        foreach ($section in @('terrainTemplates', 'topologyTemplates', 'transportTemplates', 'roadConnectionTemplates', 'carparks')) {
            if ($Settings.cellPlanning.ContainsKey($section)) {
                Add-ZMExplicitTileTemplateReferences $Settings.cellPlanning[$section] "cellPlanning.$section" $references
            }
        }
        if ($Settings.cellPlanning.ContainsKey('topologyVariants') -and
            $Settings.cellPlanning.topologyVariants -is [System.Collections.IDictionary] -and
            $Settings.cellPlanning.topologyVariants.ContainsKey('templates')) {
            Add-ZMExplicitTileTemplateReferences $Settings.cellPlanning.topologyVariants.templates 'cellPlanning.topologyVariants.templates' $references
        }
    }
    if ($Settings.ContainsKey('vmfBuild') -and $Settings.vmfBuild -is [System.Collections.IDictionary]) {
        foreach ($section in @('border', 'outerEdges')) {
            if ($Settings.vmfBuild.ContainsKey($section)) {
                Add-ZMExplicitTileTemplateReferences $Settings.vmfBuild[$section] "vmfBuild.$section" $references
            }
        }
    }

    $root = [System.IO.Path]::GetFullPath($TemplateRoot).TrimEnd('\') + '\'
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($reference in $references) {
        $relativePath = ([string]$reference.template).Replace('/', '\')
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
        if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "$($reference.setting) escapes the configured tile template directory: $($reference.template)"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missing.Add("$($reference.setting) -> $($reference.template)") | Out-Null
        }
    }
    if ($missing.Count -gt 0) {
        throw "Configured tile template paths are missing:`n$($missing -join "`n")"
    }
    return $references.Count
}

Export-ModuleMember -Function Assert-ZMRequiredMotorwayTemplateSettings, Assert-ZMConfiguredTileTemplatePaths
