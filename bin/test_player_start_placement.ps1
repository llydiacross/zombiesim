param(
    [string]$WorldProfile = 'preview',
    [string]$PlanData = '',
    [string]$CellDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PlanData)) {
    $prefix = if ($WorldProfile -eq 'city') { 'map' } else { 'preview' }
    $PlanData = Join-Path $PSScriptRoot "${prefix}_grid_$(if ($WorldProfile -eq 'city') { '64x64' } else { '24x24' })_seed_1337_template_plan.json"
}
if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path $projectRoot "generated/player_start_check_$WorldProfile"
}

$plan = Get-Content -Raw -LiteralPath $PlanData | ConvertFrom-Json
$required = @($plan.requiredCellFiles | Select-Object -ExpandProperty filename -Unique)
if ($required.Count -eq 0) { throw "Plan contains no recipe maps: $PlanData" }

& (Join-Path $PSScriptRoot 'build_cell_vmfs.ps1') -WorldProfile $WorldProfile -PlanData $PlanData -CellDirectory $CellDirectory -Force -PruneStaleGenerated | Out-Null
if (-not $?) { throw 'Cell VMF builder failed.' }

$tileGridSize = [int]$plan.cellTileGridSize
$center = [int][Math]::Floor($tileGridSize / 2)
foreach ($mapName in $required) {
    $vmfPath = Join-Path $CellDirectory $mapName
    $contents = Get-Content -Raw -LiteralPath $vmfPath
    $classIndex = $contents.IndexOf('"classname" "info_player_start"', [System.StringComparison]::Ordinal)
    if ($classIndex -lt 0) { throw "Generated VMF has no info_player_start: $mapName" }
    $originMatch = [regex]::Match($contents.Substring($classIndex), '"origin"\s+"(-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?)"')
    if (-not $originMatch.Success) { throw "Generated player start has no numeric origin: $mapName" }
    $coordinates = @($originMatch.Groups[1].Value -split '\s+' | ForEach-Object { [double]$_ })
    $tileX = [int][Math]::Round(($coordinates[0] / 640.0) + $center)
    $tileY = [int][Math]::Round($center - ($coordinates[1] / 640.0))
    if ($tileX -lt 0 -or $tileX -ge $tileGridSize -or $tileY -lt 0 -or $tileY -ge $tileGridSize) {
        throw "Player start lies outside the playable tile grid in $mapName at $($coordinates[0]),$($coordinates[1])."
    }
    $recipes = @($plan.cells | Where-Object { $_.cellTemplateFilename -eq $mapName })
    if ($recipes.Count -eq 0) { throw "No planned recipe maps to $mapName" }
    $recipe = $recipes[0]
    $placement = @($recipe.tilePlacements | Where-Object { [int]$_.tileX -eq $tileX -and [int]$_.tileY -eq $tileY })[0]
    if ($null -eq $placement -or $placement.role -ne 'terrain') {
        throw "Player start for $mapName at tile $tileX,$tileY is not on representative recipe terrain (role=$($placement.role))."
    }
}

Write-Output "Player-start placement passed: profile=$WorldProfile; recipes=$($required.Count); all starts on playable terrain tiles."
