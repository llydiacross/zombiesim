param([string]$CompiledDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$builder = Join-Path $root 'bin\build_prefab_road_preview.ps1'
$unusedOutput = Join-Path $root ('generated\prefab_road_plan_test_' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'tiletemplates\roads\tile_road.vmf'
$passed = 0
function Assert-Road([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Prefab road preview: $Message" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Road $rejected $Message
}

$before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$plan = & $builder -OutputDirectory $unusedOutput
Assert-Road (-not (Test-Path -LiteralPath $unusedOutput)) 'Planning does not create generated outputs.'
Assert-Road ($plan.sourceSha256 -ceq $before) 'Plan refers to the current authored road source.'
Assert-Road ($plan.triangles -gt 0 -and @($plan.materials).Count -eq 5) 'All five road materials resolve for the extracted geometry.'
Assert-Road ($plan.model -cmatch '^models/zombiesim/prefab_tile_preview/road_[a-f0-9]{12}_v1\.mdl$') 'The model path is deterministic and scoped.'
Assert-Road (@($plan.limitations | Where-Object { $_ -like '*Bottom ground faces*' }).Count -eq 1) 'The omitted underside is disclosed.'
Assert-Rejected { & $builder -OutputDirectory $root } 'Output outside generated is rejected.'
Assert-Rejected { & $builder -OutputDirectory (Join-Path $root 'generated') } 'The generated root cannot be used as an output.'
Assert-Road ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $before) 'Planning does not alter the authored source.'

if ($CompiledDirectory) {
    $reportPath = Join-Path $CompiledDirectory 'report.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Compiled preview report is missing: $reportPath" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Assert-Road ($report.sourceSha256 -ceq $before -and $report.model -ceq $plan.model) 'Compiled report matches current source and planned model.'
    Assert-Road ($report.bounds.min[0] -eq -320 -and $report.bounds.min[1] -eq -320 -and
        $report.bounds.max[0] -eq 320 -and $report.bounds.max[1] -eq 320) 'Compiled mesh preserves the 640x640 footprint.'
    $modelPath = $report.model.Replace('/', '\')
    $modelBase = Join-Path (Join-Path $CompiledDirectory 'game') $modelPath.Substring(0, $modelPath.Length - 4)
    foreach ($extension in @('.mdl', '.vvd', '.dx90.vtx')) {
        Assert-Road (Test-Path -LiteralPath "$modelBase$extension" -PathType Leaf) "Compiled model has its $extension companion."
    }
}
Write-Output "Prefab road preview: $passed assertions passed."
