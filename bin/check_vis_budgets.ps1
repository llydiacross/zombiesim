param(
    [string]$RequiredCellList = '',
    [Alias('MapDirectory')]
    [string]$CellDirectory = '',
    [string]$BuildDirectory = '',
    [int]$MaxPortalClusters = 0,
    [int]$MaxPortals = 0,
    [string]$ReportPath = '',
    [switch]$RefreshPortalData,
    [switch]$ListOnly,
    [string]$WorldProfile = '',
    [switch]$Preview,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BudgetValue {
    param(
        [hashtable]$Settings,
        [string]$Name,
        [int]$Fallback
    )

    if ($Settings.ContainsKey('compilation') -and $Settings.compilation.ContainsKey('visibilityBudget') -and $Settings.compilation.visibilityBudget.ContainsKey($Name)) {
        return [int]$Settings.compilation.visibilityBudget[$Name]
    }
    return $Fallback
}

function Get-TileMetrics {
    param([string]$TilePath)

    $content = Get-Content -LiteralPath $TilePath -Raw
    $totalSolids = 0
    $detailSolids = 0
    $nonDetailSolids = 0
    $braceDepth = 0
    $entityDepth = -1
    $entityClass = ''
    $pendingEntity = $false
    $pendingSolid = $false
    foreach ($line in ($content -split "`r?`n")) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq 'entity') { $pendingEntity = $true }
        if ($trimmedLine -eq 'solid') { $pendingSolid = $true }
        if ($trimmedLine -match '^"classname"\s+"(?<className>[^"]+)"$' -and $entityDepth -ge 0) {
            $entityClass = $Matches.className
        }
        if ($trimmedLine -eq '{') {
            $braceDepth++
            if ($pendingEntity) {
                $entityDepth = $braceDepth
                $entityClass = ''
                $pendingEntity = $false
            }
            if ($pendingSolid) {
                $totalSolids++
                if ($entityClass -eq 'func_detail') {
                    $detailSolids++
                } else {
                    $nonDetailSolids++
                }
                $pendingSolid = $false
            }
        }
        if ($trimmedLine -eq '}') {
            if ($braceDepth -eq $entityDepth) {
                $entityDepth = -1
                $entityClass = ''
            }
            $braceDepth--
        }
    }

    return [pscustomobject]@{
        solids = $totalSolids
        nonDetailSolids = $nonDetailSolids
        detailSolids = $detailSolids
        funcDetails = ([regex]::Matches($content, '"classname"\s+"func_detail"')).Count
        props = ([regex]::Matches($content, '"classname"\s+"prop_(static|dynamic|physics|detail)"')).Count
        entities = ([regex]::Matches($content, '"classname"\s+"')).Count
    }
}

function Get-RecipeTileDiagnostics {
    param(
        [string]$RecipePath,
        [hashtable]$TileMetricsCache
    )

    if (-not (Test-Path -LiteralPath $RecipePath -PathType Leaf)) { return @() }
    $recipeDirectory = Split-Path -Parent $RecipePath
    $recipeContent = Get-Content -LiteralPath $RecipePath -Raw
    $instanceMatches = [regex]::Matches($recipeContent, '(?ms)entity\s*\{.*?"classname"\s+"func_instance".*?"file"\s+"(?<file>[^"]+)"')
    $tileUsage = @{}
    foreach ($instanceMatch in $instanceMatches) {
        $relativeTilePath = $instanceMatch.Groups['file'].Value.Replace('/', '\')
        $tilePath = [System.IO.Path]::GetFullPath((Join-Path $recipeDirectory $relativeTilePath))
        if (-not (Test-Path -LiteralPath $tilePath -PathType Leaf)) { continue }
        if (-not $TileMetricsCache.ContainsKey($tilePath)) {
            $TileMetricsCache[$tilePath] = Get-TileMetrics $tilePath
        }
        if (-not $tileUsage.ContainsKey($tilePath)) {
            $tileUsage[$tilePath] = [ordered]@{ count = 0; metrics = $TileMetricsCache[$tilePath] }
        }
        $tileUsage[$tilePath].count++
    }

    return @($tileUsage.GetEnumerator() | ForEach-Object {
        $metrics = $_.Value.metrics
        $usageCount = [int]$_.Value.count
        $tilePath = $_.Key
        $tileDisplayPath = if ($tilePath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tilePath.Substring($projectRoot.Length).TrimStart('\').Replace('\', '/')
        } else {
            $tilePath
        }
        [pscustomobject]@{
            tile = $tileDisplayPath
            instances = $usageCount
            solids = $metrics.solids
            nonDetailSolids = $metrics.nonDetailSolids
            detailSolids = $metrics.detailSolids
            funcDetails = $metrics.funcDetails
            props = $metrics.props
            entities = $metrics.entities
            nonDetailSolidContribution = $metrics.nonDetailSolids * $usageCount
        }
    } | Sort-Object nonDetailSolidContribution, solids, entities -Descending)
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$worldGenerationProfile = & (Join-Path $PSScriptRoot 'resolve_world_generation_profile.ps1') -WorldProfile $WorldProfile -Preview:$Preview -SettingsPath $SettingsPath
$profileSettings = $worldGenerationProfile.Config

if ([string]::IsNullOrWhiteSpace($RequiredCellList)) {
    $requiredListPattern = "$($profileSettings.filePrefix)_grid_*_required_cell_vmfs.txt"
    $RequiredCellList = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $requiredListPattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($RequiredCellList) -or -not (Test-Path -LiteralPath $RequiredCellList -PathType Leaf)) {
    throw 'A required-cell list is required. Pass -RequiredCellList with a *_required_cell_vmfs.txt path.'
}
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot $profileSettings.buildDirectory
}
if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path $projectRoot $profileSettings.cellDirectory
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $BuildDirectory 'vis-budget-report.json'
}
if ($MaxPortalClusters -lt 1) {
    $MaxPortalClusters = Get-BudgetValue $worldGenerationProfile.Settings 'maxPortalClusters' 250
}
if ($MaxPortals -lt 1) {
    $MaxPortals = Get-BudgetValue $worldGenerationProfile.Settings 'maxPortals' 900
}
if ($MaxPortalClusters -lt 1 -or $MaxPortals -lt 1) {
    throw 'Visibility budgets must be greater than zero.'
}

$requiredVmfFiles = @(Get-Content -LiteralPath $RequiredCellList |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -match '\.vmf$' } |
    Sort-Object -Unique)
if ($requiredVmfFiles.Count -eq 0) {
    throw "No .vmf filenames were found in $RequiredCellList"
}

if ($RefreshPortalData) {
    $compileArguments = @{
        BuildDirectory = $BuildDirectory
        MapFilename = $requiredVmfFiles
        WorldProfile = $worldGenerationProfile.Name
        VBSPOnly = $true
        Force = $true
        SettingsPath = $SettingsPath
    }
    & (Join-Path $PSScriptRoot 'compile_cell_vmfs.ps1') @compileArguments
}

$results = [System.Collections.Generic.List[object]]::new()
$tileMetricsCache = @{}
foreach ($vmfFilename in $requiredVmfFiles) {
    $mapName = [System.IO.Path]::GetFileNameWithoutExtension($vmfFilename)
    $portalPath = Join-Path $BuildDirectory "$mapName.prt"
    if (-not (Test-Path -LiteralPath $portalPath -PathType Leaf)) {
        $results.Add([pscustomobject]@{
            map = $vmfFilename
            portalClusters = $null
            portals = $null
            status = 'missing-portal-file'
            tileDiagnostics = @()
        })
        continue
    }

    $header = @(Get-Content -LiteralPath $portalPath -TotalCount 3)
    if ($header.Count -lt 3 -or $header[0].Trim() -ne 'PRT1' -or $header[1].Trim() -notmatch '^\d+$' -or $header[2].Trim() -notmatch '^\d+$') {
        $results.Add([pscustomobject]@{
            map = $vmfFilename
            portalClusters = $null
            portals = $null
            status = 'invalid-portal-file'
            tileDiagnostics = @()
        })
        continue
    }

    $portalClusters = [int]$header[1].Trim()
    $portals = [int]$header[2].Trim()
    $overClusterBudget = $portalClusters -gt $MaxPortalClusters
    $overPortalBudget = $portals -gt $MaxPortals
    $tileDiagnostics = if ($overClusterBudget -or $overPortalBudget) {
        Get-RecipeTileDiagnostics (Join-Path $CellDirectory $vmfFilename) $tileMetricsCache
    } else {
        @()
    }
    $results.Add([pscustomobject]@{
        map = $vmfFilename
        portalClusters = $portalClusters
        portals = $portals
        status = if ($overClusterBudget -or $overPortalBudget) { 'over-budget' } else { 'within-budget' }
        tileDiagnostics = $tileDiagnostics
    })
}

$orderedResults = @($results | Sort-Object @{ Expression = { if ($null -eq $_.portals) { [int]::MaxValue } else { $_.portals } }; Descending = $true }, @{ Expression = { if ($null -eq $_.portalClusters) { [int]::MaxValue } else { $_.portalClusters } }; Descending = $true }, map)
$overBudgetResults = @($orderedResults | Where-Object { $_.status -eq 'over-budget' })
$invalidResults = @($orderedResults | Where-Object { $_.status -in @('missing-portal-file', 'invalid-portal-file') })
$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    worldProfile = $worldGenerationProfile.Name
    requiredCellList = $RequiredCellList
    buildDirectory = $BuildDirectory
    maxPortalClusters = $MaxPortalClusters
    maxPortals = $MaxPortals
    checkedCount = $orderedResults.Count
    overBudgetCount = $overBudgetResults.Count
    invalidCount = $invalidResults.Count
    maps = $orderedResults
}

$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory) {
    [System.IO.Directory]::CreateDirectory($reportDirectory) | Out-Null
}
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

if (-not $ListOnly) {
    Write-Output "Checked recipes: $($orderedResults.Count); portal-cluster budget: $MaxPortalClusters; portal budget: $MaxPortals; over budget: $($overBudgetResults.Count); invalid or missing .prt files: $($invalidResults.Count); report: $ReportPath"
}
foreach ($result in @($overBudgetResults + $invalidResults)) {
    $clusterCount = if ($null -eq $result.portalClusters) { '-' } else { $result.portalClusters }
    $portalCount = if ($null -eq $result.portals) { '-' } else { $result.portals }
    Write-Output "$($result.status): $($result.map); clusters: $clusterCount; portals: $portalCount"
    foreach ($tile in @($result.tileDiagnostics)) {
        Write-Output "  tile: $($tile.tile) x$($tile.instances); non-detail solids: $($tile.nonDetailSolids); detail solids: $($tile.detailSolids); entities: $($tile.entities); props: $($tile.props)"
    }
}

if ($overBudgetResults.Count -gt 0 -or $invalidResults.Count -gt 0) {
    exit 1
}