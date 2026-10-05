Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$gameDirectory = Split-Path -Parent (Split-Path -Parent $projectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $gameDirectory 'gameinfo.txt') -PathType Leaf)) {
    throw "Installed Garry's Mod game directory not found: $gameDirectory"
}
$catalogPath = Join-Path $projectRoot 'content\data_static\zombiesim_signs_preview.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$files = [System.Collections.Generic.List[string]]::new()
foreach ($file in 'alert_billboard.vtf', 'alert_billboard.vmt', 'alert_billboard_lit.vmt',
    'billboard_legs.vmt', 'billboard_rim.vmt', 'billboard_back.vmt', 'billboard_lamp.vmt', 'billboard_lamp.vtf') {
    $files.Add("materials\models\zombiesim\signs\$file")
}
foreach ($variant in $catalog.variants.PSObject.Properties) {
    $model = [string]$variant.Value.model
    if ($model -notmatch '^models/zombiesim/signs/alert_billboard(?:_(panel|illuminated|wall|print|poster))?\.mdl$') {
        throw "Unexpected development sign model path: $model"
    }
    $base = $model.Substring(0, $model.Length - 4).Replace('/', '\')
    $required = if ($variant.Value.collision) { @('.mdl', '.vvd', '.dx90.vtx', '.phy') } else { @('.mdl', '.vvd', '.dx90.vtx') }
    foreach ($extension in $required) { $files.Add("$base$extension") }
    foreach ($extension in '.dx80.vtx', '.sw.vtx') {
        if (Test-Path -LiteralPath (Join-Path $projectRoot "content\$base$extension") -PathType Leaf) {
            $files.Add("$base$extension")
        }
    }
}
foreach ($relative in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "content\$relative") -PathType Leaf)) {
        throw "Build the sign assets before staging; missing content\$relative"
    }
}
$results = foreach ($relative in $files) {
    $source = Join-Path $projectRoot "content\$relative"
    $destination = Join-Path $gameDirectory $relative
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
    if (-not (Test-Path -LiteralPath $destination) -or
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash) {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash) {
        throw "Development sign staging hash mismatch: $destination"
    }
    [pscustomobject]@{ path = $relative; sha256 = $hash }
}
$reportDirectory = Join-Path $projectRoot 'generated\signs_preview'
$null = New-Item -ItemType Directory -Force -Path $reportDirectory
[pscustomobject]@{ gameDirectory = $gameDirectory; files = @($results) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportDirectory 'staging-report.json') -Encoding UTF8
Write-Host "Staged and hash-verified $($files.Count) sign files into $gameDirectory (development only)."
