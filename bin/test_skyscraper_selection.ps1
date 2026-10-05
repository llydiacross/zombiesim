param([string]$PlanPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile preview
$plannerSettings = $profile.Settings.cellPlanning
$skyscraperCenterPercent = [int]$plannerSettings.buildingSelection.skyscraperCenterPercent
$skyscraperEdgePercent = [int]$plannerSettings.buildingSelection.skyscraperEdgePercent
$filenameAbbreviations = $plannerSettings.filenameAbbreviations
$worldGenerationProfile = $profile
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'plan_cell_templates.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$functionNames = @('Get-SkyscraperChancePercent', 'Test-SkyscraperPreference', 'Get-PlannerTileHash', 'Get-BuildingHeightTier', 'Get-BuildingTemplatesForDensity', 'Get-CellFilename', 'Get-MacroLayoutFilenameCode', 'Get-CompactMacroTemplateCode', 'Get-CompactMacroRotationCode', 'ConvertTo-FilenamePart')
foreach ($name in $functionNames) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false))
    if ($definition.Count -ne 1) { throw "Expected exactly one planner function $name." }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

$center = Get-SkyscraperChancePercent ([pscustomobject]@{ x = 12; y = 12 }) 25
if ($center -ne 40) { throw "Expected center chance 40, got $center." }
foreach ($point in @(@(0, 12), @(24, 12), @(12, 0), @(12, 24), @(0, 0), @(24, 24))) {
    $chance = Get-SkyscraperChancePercent ([pscustomobject]@{ x = $point[0]; y = $point[1] }) 25
    if ($chance -ne 5) { throw "Expected edge chance 5 at $point, got $chance." }
}
$previous = 40
for ($x = 12; $x -le 24; $x++) {
    $chance = Get-SkyscraperChancePercent ([pscustomobject]@{ x = $x; y = 12 }) 25
    $mirror = Get-SkyscraperChancePercent ([pscustomobject]@{ x = 24 - $x; y = 12 }) 25
    if ($chance -gt $previous -or $chance -ne $mirror) { throw 'Center taper must be monotonic and symmetric.' }
    $previous = $chance
}
if ((Get-SkyscraperChancePercent ([pscustomobject]@{ x = 0; y = 0 }) 1) -ne 40) { throw 'Single-cell world must use center chance.' }
foreach ($seed in @(1337, 2026, 42)) {
    $centerHits = 0
    $edgeHits = 0
    for ($index = 0; $index -lt 10000; $index++) {
        $roll = (Get-PlannerTileHash ($seed + $index) ($index % 5) ([int][Math]::Floor($index / 5)) 601) % 100
        if ($roll -lt 40) { $centerHits++ }
        if ($roll -lt 5) { $edgeHits++ }
    }
    if ([Math]::Abs($centerHits / 100.0 - 40) -gt 2 -or [Math]::Abs($edgeHits / 100.0 - 5) -gt 1) {
        throw "Selection frequency outside tolerance for seed ${seed}: center=$centerHits edge=$edgeHits."
    }
}
$templates = @('buildings/tile_skyscraper_1a_2x.vmf', 'buildings/tile_skyscraper_1aa_2x.vmf', 'buildings/tile_skyscraper_1aaa_2x.vmf')
foreach ($template in $templates) {
    if ($template -notmatch $plannerSettings.templatePatterns.genericBuildings) { throw "$template must be an ordinary building." }
    if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "tiletemplates\$template"))) { throw "$template is missing." }
    foreach ($pattern in $plannerSettings.landmarkTemplatePatterns.Values) {
        if ($template -like $pattern) { throw "$template must not be a landmark." }
    }
}
$short = @(Get-BuildingTemplatesForDensity $templates 1)
$tall = @(Get-BuildingTemplatesForDensity $templates 3)
if (@($short | Where-Object { $_ -eq $templates[0] }).Count -le @($short | Where-Object { $_ -eq $templates[2] }).Count -or
    @($tall | Where-Object { $_ -eq $templates[2] }).Count -le @($tall | Where-Object { $_ -eq $templates[0] }).Count) {
    throw 'Existing height-tier preference must be preserved within the tower family.'
}
$codes = [pscustomobject]@{
    environment = 'd'; topology = 'rs'; orientation = 'v'; transport = ''; density = 'd1'
    landmarks = @(); macro = ''; safeZoneEntrance = ''; skyscraperChance = 5; skyscraperPreferred = $false
}
$edgeFilename = Get-CellFilename $codes
$codes.skyscraperChance = 40
$centerFilename = Get-CellFilename $codes
if ($edgeFilename -ne $centerFilename -or $centerFilename -ne (Get-CellFilename $codes)) {
    throw 'Identical layouts must share recipe identity regardless of selection probability.'
}
$codes.skyscraperPreferred = $true
if ($centerFilename -ne (Get-CellFilename $codes)) { throw 'Preference alone must not split identical layouts.' }
$codes.macro = 'm22-skyscraper_1aaa-p1-1-n'
if ($centerFilename -eq (Get-CellFilename $codes)) { throw 'Actual tower macro layouts must remain distinct.' }
$map = [pscustomobject]@{ map = [pscustomobject]@{ seed = 1337 } }
$mapGridCells = 25
$cell = [pscustomobject]@{ x = 12; y = 12 }
if ((Test-SkyscraperPreference $cell) -ne (Test-SkyscraperPreference $cell)) { throw 'World-cell preference must be deterministic.' }
if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    $plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
    $halfSpan = ($plan.mapGridCells - 1) / 2.0
    $rows = foreach ($plannedCell in $plan.cells) {
        $towers = @($plannedCell.tilePlacements | Where-Object {
            $_.template -match 'tile_skyscraper_' -and
            ($null -eq $_.PSObject.Properties['emitsInstance'] -or $_.emitsInstance)
        })
        foreach ($tower in $towers) {
            if ($tower.role -ne 'building' -or $tower.template -notmatch '_2x\.vmf$') { throw 'Tower must be an ordinary 2x building.' }
        }
        [pscustomobject]@{
            distance = [Math]::Max([Math]::Abs($plannedCell.x - $halfSpan), [Math]::Abs($plannedCell.y - $halfSpan)) / $halfSpan
            towers = $towers.Count
        }
    }
    $central = @($rows | Where-Object { $_.distance -lt 0.5 })
    $outer = @($rows | Where-Object { $_.distance -ge 0.8 })
    if ($central.Count -eq 0 -or $outer.Count -eq 0) { throw 'Plan must cover both central and outer bands.' }
    $centralCount = ($central | Measure-Object towers -Sum).Sum
    $outerCount = ($outer | Measure-Object towers -Sum).Sum
    if ($centralCount / $central.Count -le $outerCount / $outer.Count) { throw 'Realized central tower concentration must exceed outer concentration.' }
    foreach ($group in @($plan.cells | Group-Object cellTemplateFilename)) {
        $macroLayouts = @($group.Group | ForEach-Object { Get-MacroLayoutFilenameCode $_.tilePlacements } | Sort-Object -Unique)
        if ($macroLayouts.Count -gt 1) { throw "Shared recipe $($group.Name) has conflicting multi-tile layouts." }
        $layouts = @($group.Group | ForEach-Object {
            (@($_.tilePlacements | Where-Object { $_.template -match 'tile_skyscraper_' } | Sort-Object tileY, tileX | ForEach-Object {
                "$($_.tileX),$($_.tileY),$($_.rotationYaw),$($_.template)"
            }) -join ';')
        } | Sort-Object -Unique)
        if ($layouts.Count -gt 1) { throw "Shared recipe $($group.Name) has conflicting tower layouts." }
    }
    $cityRecipeCount = @($plan.requiredCellFiles).Count
    $denRecipeCount = @($plan.safeZoneMaps.mapFilename | Sort-Object -Unique).Count
    Write-Output "Required BSP count: city=$cityRecipeCount, uniqueDens=$denRecipeCount, total=$($cityRecipeCount + $denRecipeCount)."
    Write-Output "Realized taper passed: center=$centralCount/$($central.Count) outer=$outerCount/$($outer.Count), shared recipes consistent."
}
Write-Output 'Skyscraper selection passed: center/edges, symmetry/taper, three-seed frequency, ordinary classification, height preference, deterministic recipe identity.'
