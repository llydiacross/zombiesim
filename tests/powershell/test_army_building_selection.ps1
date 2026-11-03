Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
Import-Module (Join-Path $testsBinDirectory 'scenery_density.psm1') -Force
$root = $testsRepoRoot
$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Army building selection: $Message" }
    $script:passed++
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $testsBinDirectory 'plan_cell_templates.ps1'), [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Planner parses.'
$definition = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ProfileFallbackTemplates'
}, $false))
Assert ($definition.Count -eq 1) 'One production profile building-pool selector exists.'
. ([scriptblock]::Create($definition[0].Extent.Text))

$armyDirectory = Join-Path (Join-Path $root 'tiletemplates') 'army'
$script:armyBuildingTemplates = @(Get-ChildItem -LiteralPath $armyDirectory -Filter '*.vmf' -File -Recurse |
    ForEach-Object { $_.FullName.Substring((Join-Path $root 'tiletemplates').Length + 1).Replace('\', '/') } |
    Sort-Object)
Assert ($armyBuildingTemplates.Count -gt 0) 'The current Army template pool is available.'
foreach ($template in @('tile_army_guardtower.vmf', 'tile_army_hanger.vmf', 'tile_army_tent3.vmf', 'tile_army_truck.vmf', 'tile_army_truck2.vmf')) {
    Assert ($armyBuildingTemplates -contains "army/$template") "The new Army pool includes $template."
}
$selectionCases = @(
    @{ label = 'Military profile'; profile = 'military'; landmarks = @() },
    @{ label = 'Army Base landmark cell'; profile = 'safe_zone'; landmarks = @('Army Base') }
)
foreach ($case in $selectionCases) {
    $selected = @(Get-ProfileFallbackTemplates ([pscustomobject]@{ x = 0; y = 0 }) $case.profile $case.landmarks)
    Assert (($selected -join ',') -ceq ($armyBuildingTemplates -join ',')) "$($case.label) building selection uses every Army-folder VMF and no generic/warehouse/commercial/industry templates."
    Assert (@($selected | Where-Object { $_ -notmatch '^army/.*\.vmf$' }).Count -eq 0) "$($case.label) selection excludes every building outside tiletemplates/army."
}

$settings = (& (Join-Path $testsBinDirectory 'resolve_world_generation_profile.ps1') -WorldProfile preview).Settings
$script:fortifiedBuildingTemplates = @(Get-ChildItem -LiteralPath (Join-Path $root 'tiletemplates\buildings') -Filter '*.vmf' -File |
    ForEach-Object { 'buildings/' + $_.Name } |
    Where-Object { $_ -match $settings.cellPlanning.templatePatterns.fortifiedBuildings } |
    Sort-Object)
foreach ($template in @('tile_fortified_1a.vmf', 'tile_fortified_1aa.vmf', 'tile_fortified_3aa.vmf')) {
    Assert ($fortifiedBuildingTemplates -contains "buildings/$template") "The fortified pool includes $template."
}
$script:destroyedBuildingTemplates = @()
$script:radioactiveBuildingTemplates = @()
$script:buildingTemplates = @()
$script:warehouseTemplates = @()
$currentCell = [pscustomobject]@{ x = 0; y = 0; sceneryDensityPolicyVersion = 2 }
$fortifiedPool = @(Get-ProfileFallbackTemplates $currentCell 'fortified' @())
Assert (($fortifiedPool -join ',') -ceq (($armyBuildingTemplates + $fortifiedBuildingTemplates) -join ',')) 'Policy-v2 fortified cells admit both authored families.'
$militaryPool = @(Get-ProfileFallbackTemplates $currentCell 'military' @())
Assert (($militaryPool -join ',') -ceq ($armyBuildingTemplates -join ',')) 'Policy-v2 military cells retain only the Army family.'

$script:armyBuildingTemplates = @()
foreach ($case in $selectionCases) {
    $rejected = $false
    try {
        Get-ProfileFallbackTemplates ([pscustomobject]@{ x = 0; y = 0 }) $case.profile $case.landmarks | Out-Null
    } catch {
        if ($_.Exception.Message -notlike '*requires VMFs under tiletemplates\army*') { throw }
        $rejected = $true
    }
    Assert $rejected "$($case.label) selection fails explicitly if its Army-only pool is empty."
}

$settingsText = [IO.File]::ReadAllText((Join-Path $root 'generator-settings.json'))
$chanceSetting = '"fortifiedThemedChancePercent": 80'
Assert ($settingsText.Contains($chanceSetting)) 'The current settings contain the expected fortified preference.'
foreach ($invalid in @('null', '-1', '101', '80.5')) {
    $temporarySettings = Join-Path ([IO.Path]::GetTempPath()) ("zombiesim-fortified-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporarySettings, $settingsText.Replace($chanceSetting, ('"fortifiedThemedChancePercent": ' + $invalid)))
        $rejected = $false
        try {
            & (Join-Path $testsBinDirectory 'plan_cell_templates.ps1') -WorldProfile preview -SettingsPath $temporarySettings -MapData 'missing-fixture.json' | Out-Null
        } catch {
            if ($_.Exception.Message -notlike '*fortifiedThemedChancePercent must be an integer from 0 through 100*') { throw }
            $rejected = $true
        }
        Assert $rejected "An invalid fortified preference ($invalid) fails before planning."
    } finally {
        if (Test-Path -LiteralPath $temporarySettings) { Remove-Item -LiteralPath $temporarySettings }
    }
}

Write-Output "Army building selection: $passed assertions passed; military and fortified building pools are scoped to their intended districts."
