Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
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
$selectionCases = @(
    @{ label = 'Military profile'; profile = 'military'; landmarks = @() },
    @{ label = 'Army Base landmark cell'; profile = 'safe_zone'; landmarks = @('Army Base') }
)
foreach ($case in $selectionCases) {
    $selected = @(Get-ProfileFallbackTemplates ([pscustomobject]@{ x = 0; y = 0 }) $case.profile $case.landmarks)
    Assert (($selected -join ',') -ceq ($armyBuildingTemplates -join ',')) "$($case.label) building selection uses every Army-folder VMF and no generic/warehouse/commercial/industry templates."
    Assert (@($selected | Where-Object { $_ -notmatch '^army/.*\.vmf$' }).Count -eq 0) "$($case.label) selection excludes every building outside tiletemplates/army."
}

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

Write-Output "Army building selection: $passed assertions passed; military-profile and Army Base landmark buildings are restricted to tiletemplates/army."
