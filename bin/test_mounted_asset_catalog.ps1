param(
    [string]$CatalogPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'mounted_asset_catalog.psm1') -Force

$checks = 0
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Check {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Get-JsonValue {
    param($Object, [string]$Name)

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

$duplicateFixture = @(Merge-CatalogModelEntries `
    -ArchiveEntries @(
        [pscustomobject]@{ model = 'MODELS\Props\Crate.MDL'; sourceArchive = 'addon/disabled_dir.vpk'; mounted = $false },
        [pscustomobject]@{ model = 'models/props/crate.mdl'; sourceArchive = 'sourceengine/core_dir.vpk'; mounted = $true }
    ) `
    -References @([pscustomobject]@{ model = 'Models/Props/CRATE.mdl'; itemId = 'itemFixture'; usage = 'iconModel' }))
Assert-Check ($duplicateFixture.Count -eq 1) 'duplicate case/slash aliases must deduplicate to one model'
Assert-Check ($duplicateFixture[0].mounted) 'an asset found in a mounted archive must remain mounted after alias merging'
Assert-Check ($duplicateFixture[0].suitableForItem) 'an explicit icon model reference must be marked item-suitable'
Assert-Check ($duplicateFixture[0].sourceArchives.Count -eq 2) 'deduplicated assets must retain every source archive'

$missingFixture = @(Merge-CatalogModelEntries -References @(
    [pscustomobject]@{ model = 'models/missing/candidate.mdl'; itemId = 'missingItem'; usage = 'iconModel' },
    [pscustomobject]@{ model = 'models/unmounted/candidate.mdl'; itemId = 'unmountedItem'; usage = 'viewModel' }
))
Assert-Check ($missingFixture.Count -eq 2) 'unresolved references must remain visible in the report'
Assert-Check (-not $missingFixture[0].mounted -and -not $missingFixture[1].mounted) 'missing or unmounted-only assets must not be reported as mounted'
Assert-Check ($missingFixture[0].suitableForItem -and -not $missingFixture[1].suitableForItem) 'view models must not be marked as inventory item models'
Assert-Check (Test-CatalogCandidateModel 'models/items/ammocrate_pistol.mdl') 'item-folder models should be candidates'
Assert-Check (-not (Test-CatalogCandidateModel 'materials/models/items/ammocrate_pistol.vmt')) 'non-model files must be filtered out'
Assert-Check (-not (Test-CatalogCandidateModel 'models/weapons/v_generic.mdl')) 'view models should not be candidate inventory assets'
Assert-Check (-not (Test-CatalogCandidateModel 'models/props_junk/wood_crate001a_chunk01.mdl')) 'breakable model fragments should not be candidates'

if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $repoRoot 'generated\asset_catalog\mounted_asset_catalog.json'
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    throw "Mounted asset catalog is missing. Run .\bin\build_mounted_asset_catalog.ps1 first. Expected: $CatalogPath"
}

$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
$catalogByModel = @{}
foreach ($entry in $catalog.models) {
    $canonical = ConvertTo-CatalogModelPath $entry.model
    Assert-Check ($canonical -eq $entry.model) "catalog model path is not canonical: $($entry.model)"
    Assert-Check (-not $catalogByModel.ContainsKey($canonical)) "catalog contains duplicate model: $canonical"
    $catalogByModel[$canonical] = $entry
    Assert-Check ($null -ne $entry.assetFamily -and $null -ne $entry.tags -and $null -ne $entry.sourceArchives) "catalog metadata is incomplete for $canonical"
}

$itemData = Get-Content -LiteralPath (Join-Path $repoRoot 'content\data_static\item_definitions.json') -Raw | ConvertFrom-Json
foreach ($itemProperty in $itemData.items.PSObject.Properties) {
    foreach ($field in @('iconModel', 'worldModel', 'viewModel')) {
        $model = Get-JsonValue $itemProperty.Value $field
        if ([string]::IsNullOrWhiteSpace([string]$model)) {
            continue
        }
        $canonical = ConvertTo-CatalogModelPath $model
        Assert-Check ($catalogByModel.ContainsKey($canonical)) "item reference is absent from catalog: $($itemProperty.Name).$field -> $canonical"
        if ($catalogByModel.ContainsKey($canonical)) {
            Assert-Check ([bool]$catalogByModel[$canonical].mounted) "item model is not present in a mounted archive: $($itemProperty.Name).$field -> $canonical"
            if ($field -in @('iconModel', 'worldModel')) {
                Assert-Check ([bool]$catalogByModel[$canonical].suitableForItem) "item model is not marked suitable: $($itemProperty.Name).$field -> $canonical"
            }
        }
    }
}

$entityLootData = Get-Content -LiteralPath (Join-Path $repoRoot 'content\data_static\entity_loot.json') -Raw | ConvertFrom-Json
foreach ($rule in $entityLootData.rules) {
    $model = ConvertTo-CatalogModelPath $rule.model
    Assert-Check ($catalogByModel.ContainsKey($model)) "entity loot model is absent from catalog: $model"
    if ($catalogByModel.ContainsKey($model)) {
        Assert-Check ([bool]$catalogByModel[$model].mounted) "entity loot model is not in a mounted archive: $model"
    }
}

$lootData = Get-Content -LiteralPath (Join-Path $repoRoot 'content\data_static\loot.json') -Raw | ConvertFrom-Json
$itemTable = $itemData.items
function Get-ResolvedLootItemIds {
    param([string]$GroupId, [hashtable]$Seen)

    $group = Get-JsonValue $lootData.groups $GroupId
    if ($Seen.ContainsKey($GroupId) -or -not $group) {
        return @()
    }
    $Seen[$GroupId] = $true
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($included in (Get-JsonValue $group 'include')) {
        foreach ($itemId in Get-ResolvedLootItemIds -GroupId $included -Seen $Seen) {
            $ids.Add($itemId)
        }
    }
    $groupItems = Get-JsonValue $group 'items'
    if ($groupItems) {
        foreach ($property in $groupItems.PSObject.Properties) {
            $ids.Add($property.Name)
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Assert-RuleGroup {
    param([string]$Model, [string]$ExpectedGroup)

    $rule = @($entityLootData.rules | Where-Object { (ConvertTo-CatalogModelPath $_.model) -eq $Model })
    Assert-Check ($rule.Count -eq 1) "expected exactly one semantic rule for $Model"
    if ($rule.Count -eq 1) {
        Assert-Check ($rule[0].lootGroups -contains $ExpectedGroup) "$Model must use $ExpectedGroup"
    }
}

Assert-RuleGroup 'models/props/cs_office/vending_machine.mdl' 'lootVendingDrinks'
Assert-RuleGroup 'models/props_interiors/vendingmachinesoda01a.mdl' 'lootVendingDrinks'
Assert-RuleGroup 'models/items/ammocrate_pistol.mdl' 'lootMilitarySupplies'
Assert-RuleGroup 'models/props/cs_militia/crate_extralargemill.mdl' 'lootMilitarySupplies'
Assert-RuleGroup 'models/props_junk/wood_crate001a.mdl' 'lootGeneralCrate'

$vendingIds = Get-ResolvedLootItemIds -GroupId 'lootVendingDrinks' -Seen @{}
Assert-Check ($vendingIds.Count -gt 0) 'vending loot must not be empty'
foreach ($itemId in $vendingIds) {
    $item = $itemTable.$itemId
    $food = Get-JsonValue $item 'food'
    Assert-Check ($food -and (Get-JsonValue $food 'hydration') -gt 0) "vending loot must contain drinks only; found $itemId"
}

$militaryIds = Get-ResolvedLootItemIds -GroupId 'lootMilitarySupplies' -Seen @{}
Assert-Check ($militaryIds.Count -gt 0) 'military loot must not be empty'
foreach ($itemId in $militaryIds) {
    $item = $itemTable.$itemId
    $isWeapon = (Get-JsonValue $item 'entityClass') -eq 'weapon'
    $isAmmo = $itemId -match '^ammo'
    Assert-Check ($isWeapon -or $isAmmo) "military loot may contain weapons/ammunition only; found $itemId"
}

$generalIds = Get-ResolvedLootItemIds -GroupId 'lootGeneralCrate' -Seen @{}
Assert-Check ($generalIds.Count -gt 0) 'ordinary crate loot must not be empty'
foreach ($itemId in $generalIds) {
    $item = $itemTable.$itemId
    $isGeneralSupply = (Get-JsonValue $item 'food') -or (Get-JsonValue $item 'medical') -or (Get-JsonValue $item 'lootCategory') -eq 'medical' -or $itemId -in @('itemScrapMetal', 'itemCloth', 'itemGunpowder')
    Assert-Check $isGeneralSupply "ordinary crate loot may contain food, medical supplies, and materials only; found $itemId"
}
Assert-Check (-not ($entityLootData.rules | Where-Object { (ConvertTo-CatalogModelPath $_.model) -eq 'models/props_junk/garbage_dumpster.mdl' })) 'unsupported props must not have a fallback loot rule'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    throw "$($failures.Count) of $checks mounted asset catalog checks failed."
}
Write-Output "Mounted asset catalog checks passed: $checks"
