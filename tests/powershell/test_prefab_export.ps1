Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exporter = Join-Path $root 'bin\export_prefab.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zombiesim-prefab-test-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $temporary 'source'
$output = Join-Path $temporary 'output'
$passed = 0
function Assert-Prefab([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Prefab export: $Message" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Prefab $rejected $Message
}

[IO.Directory]::CreateDirectory($source) | Out-Null
try {
    $path = Join-Path $source 'roadblock.json'
    $json = '{"schemaVersion":1,"id":"roadblock","name":"Roadblock","description":"","tags":["roadDetail"],"props":[{"model":"models/props_c17/oildrum001.mdl","position":{"x":0,"y":64,"z":0},"angles":{"p":0,"y":90,"r":0},"skin":0}]}'
    [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output | Out-Null
    Assert-Prefab (-not (Test-Path -LiteralPath $output)) 'Dry run changes no files.'
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply | Out-Null
    $destination = Join-Path $output 'roadblock.json'
    Assert-Prefab (Test-Path -LiteralPath $destination -PathType Leaf) 'Apply exports the document.'
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Export preserves exact source bytes.'
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Repeated identical export is safe.'

    [IO.File]::WriteAllText($path, $json.Replace('"Roadblock"', '"Changed"'), [Text.UTF8Encoding]::new($false))
    $oldHash = (Get-FileHash -LiteralPath $destination).Hash
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply } 'An existing different export cannot be overwritten accidentally.'
    Assert-Prefab ((Get-FileHash -LiteralPath $destination).Hash -eq $oldHash) 'Refused overwrite preserves the old export.'
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Explicit replacement exports the new bytes.'
    Assert-Prefab (@(Get-ChildItem -LiteralPath $output -Force -File).Count -eq 1) 'No temporary or backup files remain after success.'

    Assert-Rejected { & $exporter -Id '..\escape' -SourceDirectory $source -OutputDirectory $output -Apply } 'Unsafe IDs are rejected.'
    [IO.File]::WriteAllText($path, $json.Replace('models/props_c17/oildrum001.mdl', 'models/../bad.mdl'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Unsafe model paths are rejected.'
    [IO.File]::WriteAllText($path, $json.Replace('"schemaVersion":1', '"schemaVersion":1,"unknown":true'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Unsupported fields are rejected.'
    [IO.File]::WriteAllText($path, $json.Replace('"schemaVersion":1', '"schemaVersion":"1"'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'String schema versions are rejected.'
    [IO.File]::WriteAllText($path, $json.Replace('"skin":0', '"skin":0,"scale":2.5'), [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'A valid scaled prefab is exported.'
    [IO.File]::WriteAllText($path, $json.Replace('"skin":0', '"skin":0,"scale":0'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Zero scale is rejected.'
    [IO.File]::WriteAllText($path, $json.Replace('"skin":0', '"skin":0,"scale":10.01'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Scale beyond the supported range is rejected.'
    Assert-Prefab ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $path).Hash) 'Invalid source never overwrites the approved export.'
    foreach ($value in @('true', 'false')) {
        [IO.File]::WriteAllText($path, $json.Replace('"skin":0', ('"skin":0,"movable":' + $value)), [Text.UTF8Encoding]::new($false))
        & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
        Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) "Mobility $value exports unchanged."
    }
    foreach ($value in @('null', '0', '1', '"true"', '{}')) {
        [IO.File]::WriteAllText($path, $json.Replace('"skin":0', ('"skin":0,"movable":' + $value)), [Text.UTF8Encoding]::new($false))
        Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } "Invalid mobility $value is rejected."
    }
    $loot = $json.Replace('"skin":0', '"skin":0,"propId":"p_123","lootMode":"normal","lootGroup":"lootGenericMedical","lootChance":0.4')
    [IO.File]::WriteAllText($path, $loot, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Valid loot configuration exports unchanged.'
    foreach ($invalid in @(
        $loot.Replace('"lootMode":"normal"', '"lootMode":"unknown"'),
        $loot.Replace('"lootGroup":"lootGenericMedical"', '"lootGroup":"lootNotReal"'),
        $loot.Replace('"lootChance":0.4', '"lootChance":1.1'),
        $loot.Replace('"propId":"p_123"', '"propId":"../bad"')
    )) {
        [IO.File]::WriteAllText($path, $invalid, [Text.UTF8Encoding]::new($false))
        Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Invalid loot configuration must not export.'
    }
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Output "Prefab export: $passed assertions passed."
