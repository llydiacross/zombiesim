param([string]$PlanData = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testsBinDirectory = Join-Path $testsRepoRoot 'bin'
$root = $testsRepoRoot
Import-Module (Join-Path $testsBinDirectory 'motorway_geometry.psm1') -Force
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $testsBinDirectory 'build_cell_vmfs.ps1'),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -ne 0) { throw 'Cell VMF builder must parse.' }
$definition = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-MotorwayInfillRecipes'
}, $false))
if ($definition.Count -ne 1) { throw 'Expected one motorway infill recipe selector.' }
. ([scriptblock]::Create($definition[0].Extent.Text))

$passed = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Motorway infill scope: $Message" }
    $script:passed++
}

$normalStraight = [pscustomobject]@{
    cellTemplateFilename = 'motorway-straight.vmf'
    motorwayAssembly = [pscustomobject]@{
        schemaVersion = 2
        assemblyAuthority = 'trusted_prior_approved_grid_layout'
    }
}
$complexMotorway = [pscustomobject]@{
    cellTemplateFilename = 'motorway-crossroads.vmf'
    motorwayAssembly = [pscustomobject]@{
        schemaVersion = 2
        assemblyAuthority = 'trusted_prior_approved_grid_layout'
    }
}
$diagnosticMotorway = [pscustomobject]@{
    cellTemplateFilename = 'motorway-inspection.vmf'
    motorwayCellInspection = [pscustomobject]@{ schemaVersion = 2 }
}
$ordinary = [pscustomobject]@{ cellTemplateFilename = 'ordinary-road.vmf' }
$legacyContract = [pscustomobject]@{
    cellTemplateFilename = 'legacy-straight.vmf'
    motorwayAssembly = [pscustomobject]@{ schemaVersion = 1 }
}
$selected = @(Get-MotorwayInfillRecipes @(
    $normalStraight, $complexMotorway, $diagnosticMotorway, $ordinary, $legacyContract
))
Assert ($selected.Count -eq 2) 'Only schema-2 normal motorway assembly contracts are selected.'
Assert (@($selected | Where-Object { $_.cellTemplateFilename -eq 'ordinary-road.vmf' }).Count -eq 0) 'Ordinary recipes are excluded.'
Assert (@($selected | Where-Object { $_.cellTemplateFilename -eq 'legacy-straight.vmf' }).Count -eq 0) 'Unmeasured legacy contracts are excluded.'
Assert (@($selected | Where-Object { $_.cellTemplateFilename -eq 'motorway-straight.vmf' }).Count -eq 1) 'Normal straight motorway recipes are included.'
Assert (@($selected | Where-Object { $_.cellTemplateFilename -eq 'motorway-inspection.vmf' }).Count -eq 0) 'Retired diagnostic inspection contracts cannot enter normal infill batches.'

$rejectedEmpty = $false
try {
    Get-MotorwayInfillRecipes @($ordinary, $legacyContract) | Out-Null
} catch {
    if ($_.Exception.Message -notlike '*found no recipes with a trusted schema-2 motorway assembly*') { throw }
    $rejectedEmpty = $true
}
Assert $rejectedEmpty 'An empty motorway-only pass fails explicitly.'

if (-not [string]::IsNullOrWhiteSpace($PlanData)) {
    if (-not (Test-Path -LiteralPath $PlanData -PathType Leaf)) {
        throw "Motorway infill scope plan was not found: $PlanData"
    }
    $plan = Get-Content -LiteralPath $PlanData -Raw | ConvertFrom-Json
    $planRecipes = @($plan.cells |
        Group-Object cellTemplateFilename |
        Sort-Object Name |
        ForEach-Object { $_.Group[0] })
    $planSelected = @(Get-MotorwayInfillRecipes $planRecipes)
    $sourceDirectory = Join-Path (Split-Path -Parent $PlanData) 'src'
    foreach ($recipe in $planRecipes) {
        $layoutPath = Join-Path $sourceDirectory ([IO.Path]::ChangeExtension([string]$recipe.cellTemplateFilename, '.layout.json'))
        $vmfPath = Join-Path $sourceDirectory ([string]$recipe.cellTemplateFilename)
        if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf)) {
            throw "Current recipe layout is missing: $layoutPath"
        }
        if (-not (Test-Path -LiteralPath $vmfPath -PathType Leaf)) {
            throw "Current recipe VMF is missing: $vmfPath"
        }
        $layout = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
        $isSelected = @($planSelected | Where-Object { $_.cellTemplateFilename -eq $recipe.cellTemplateFilename }).Count -eq 1
        $hasInfill = $null -ne $layout.PSObject.Properties['terrainInfill']
        Assert ($isSelected -eq $hasInfill) "Motorway-only selection and emitted infill agree for $($recipe.cellTemplateFilename)."
        $actualHash = (Get-FileHash -LiteralPath $vmfPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert ($layout.vmfSha256 -ceq $actualHash) "Current layout fingerprint matches its VMF for $($recipe.cellTemplateFilename)."
        if ($isSelected) {
            $authority = $layout.motorwayAssembly.PSObject.Properties['assemblyAuthority']
            if ($null -ne $authority -and $authority.Value -eq 'trusted_prior_approved_grid_layout') {
                Assert ($null -eq $layout.motorwayAssembly.PSObject.Properties['sourceFingerprints']) "Trusted prior plan does not retain stale geometry fingerprints for $($recipe.cellTemplateFilename)."
                Assert (@($layout.motorwayAssembly.gates).Count -gt 0) "Trusted prior plan retains its approved gates for $($recipe.cellTemplateFilename)."
            } else {
                foreach ($fingerprint in $layout.motorwayAssembly.sourceFingerprints.PSObject.Properties) {
                    $sourcePath = Join-Path (Join-Path $root 'tiletemplates') ([string]$fingerprint.Name)
                    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                        throw "Measured motorway source is missing: $sourcePath"
                    }
                    Assert ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ceq $fingerprint.Value) "Measured motorway source fingerprint is current for $($recipe.cellTemplateFilename)."
                }
            }
            foreach ($placement in $layout.terrainInfill.placements) {
                $infillSource = Join-Path (Join-Path $root 'tiletemplates') ([string]$placement.template)
                Assert (Test-Path -LiteralPath $infillSource -PathType Leaf) "Motorway infill source exists for $($recipe.cellTemplateFilename)."
            }
        }
    }
}

Write-Output "Motorway infill scope: $passed assertions passed."
