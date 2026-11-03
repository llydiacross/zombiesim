Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'bin\plan_cell_templates.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Planner did not parse.' }
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PlanManifestReference'
}, $true))
if ($definitions.Count -ne 1) { throw 'Planner must define one manifest-reference function.' }
. ([scriptblock]::Create($definitions[0].Extent.Text))

$base = Join-Path ([IO.Path]::GetTempPath()) 'zombiesim manifest reference'
$plan = Join-Path $base 'plans\plan.json'
$cases = @(
    @{ map = (Join-Path $base 'plans\manifest.json'); expected = 'manifest.json' },
    @{ map = (Join-Path $base 'plans\world data\manifest.json'); expected = 'world data\manifest.json' },
    @{ map = (Join-Path $base 'world\manifest.json'); expected = '..\world\manifest.json' }
)
foreach ($case in $cases) {
    $actual = Get-PlanManifestReference $case.map $plan
    if ($actual -cne $case.expected) { throw "Expected '$($case.expected)', received '$actual'." }
    $resolved = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($plan)) $actual))
    if ($resolved -ine [IO.Path]::GetFullPath($case.map)) { throw "Manifest reference '$actual' does not resolve to its input." }
}
$otherDrive = if ([IO.Path]::GetPathRoot($plan) -ieq 'C:\') { 'D:\preview\manifest.json' } else { 'C:\preview\manifest.json' }
if ((Get-PlanManifestReference $otherDrive $plan) -ine $otherDrive) { throw 'A different-drive manifest must remain an absolute path.' }
Write-Output 'Plan manifest reference: same-folder, nested, sibling, spaces and different-drive cases passed.'
