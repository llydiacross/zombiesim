param(
    [string]$RequiredCellList = '',
    [Alias('MapDirectory')]
    [string]$CellDirectory = '',
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RequiredCellList)) {
    $RequiredCellList = @(Get-ChildItem -Path $PSScriptRoot -Filter '*_required_cell_vmfs.txt' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)[0].FullName
}
if ([string]::IsNullOrWhiteSpace($RequiredCellList) -or -not (Test-Path $RequiredCellList)) {
    throw 'A required-cell list is required. Pass -RequiredCellList with a *_required_cell_vmfs.txt path.'
}
if ([string]::IsNullOrWhiteSpace($CellDirectory)) {
    $CellDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'maps\src'
}
if (-not (Test-Path $CellDirectory)) {
    throw "Cell source directory was not found: $CellDirectory"
}

$requiredVmfFiles = @(Get-Content $RequiredCellList |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -match '\.vmf$' } |
    Sort-Object -Unique)
if ($requiredVmfFiles.Count -eq 0) {
    throw "No .vmf filenames were found in $RequiredCellList"
}

$authoredCells = @{}
Get-ChildItem -Path $CellDirectory -Filter '*.vmf' -File | ForEach-Object {
    $authoredCells[$_.Name.ToLowerInvariant()] = $_.Name
}

$missingCells = @($requiredVmfFiles | ForEach-Object {
    $vmfFilename = $_
    if (-not $authoredCells.ContainsKey($vmfFilename.ToLowerInvariant())) {
        [pscustomobject]@{
            vmfFilename = $vmfFilename
        }
    }
})

if (-not $ListOnly) {
    Write-Output "Required recipes: $($requiredVmfFiles.Count); authored cell VMFs found: $($authoredCells.Count); missing cells: $($missingCells.Count)"
}
$missingCells | ForEach-Object { $_.vmfFilename }

if ($missingCells.Count -gt 0) {
    exit 1
}
