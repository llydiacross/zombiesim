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
    $dryRun = & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output
    Assert-Prefab ($dryRun -like 'Would export prefab roadblock to *') 'Dry-run reporting keeps the prefab ID separate from per-prop identities.'
    Assert-Prefab (-not (Test-Path -LiteralPath $output)) 'Dry run changes no files.'
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply | Out-Null
    $destination = Join-Path $output 'roadblock.json'
    Assert-Prefab (Test-Path -LiteralPath $destination -PathType Leaf) 'Apply exports the document.'
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Export preserves exact source bytes.'
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Repeated identical export is safe.'
    $placement = '"worldPlacement":{"enabled":true,"profile":"preview","cellX":14,"cellY":0,"tileX":-2,"tileY":2,"offset":{"x":1.25,"y":-2.5,"z":3.75},"angles":{"p":0,"y":90,"r":0}},'
    $worldPrefab = $json.Replace('"props":[', ($placement + '"props":['))
    [IO.File]::WriteAllText($path, $worldPrefab, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'World placement exports with exact source bytes.'
    [IO.File]::WriteAllText($path, $worldPrefab.Replace('"enabled":true', '"enabled":false'), [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab $true 'Disabled placements can be explicitly exported.'
    foreach ($invalid in @(
        $worldPrefab.Replace('"tileX":-2', '"tileX":3'),
        $worldPrefab.Replace('"cellX":14', '"cellX":14.5'),
        $worldPrefab.Replace('"profile":"preview"', '"profile":"other"'),
        $worldPrefab.Replace('"enabled":true', '"enabled":"true"'),
        $worldPrefab.Replace('"z":3.75', '"z":32769'),
        $worldPrefab.Replace('"y":90', '"y":"90"'),
        $worldPrefab.Replace('"tileX":-2', '"extra":1,"tileX":-2')
    )) {
        [IO.File]::WriteAllText($path, $invalid, [Text.UTF8Encoding]::new($false))
        Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Malformed world placement cannot export.'
    }
    $emptyGuards = $json.Replace('"props":[', '"guards":[],"props":[')
    [IO.File]::WriteAllText($path, $emptyGuards, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Replace | Out-Null
    Assert-Prefab $true 'An empty guard list remains export-compatible.'
    $withGuard = $json.Replace('"props":[', '"guards":[{}],"props":[')
    [IO.File]::WriteAllText($path, $withGuard, [Text.UTF8Encoding]::new($false))
    Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Malformed guard records cannot export.'
    $guard = '{"guardId":"guard_1","name":"Guard","model":"models/player/group01/male_03.mdl","position":{"x":1,"y":2,"z":3},"angles":{"p":0,"y":90,"r":0},"idle":"idle_all_01","weapon":"pistol","range":1000,"shirt":"catalogue_fabric_shirt_blue_plain","pants":"catalogue_fabric_pants_black_plain","damage":25,"fireInterval":0.075,"spread":0}'
    $validGuard = $json.Replace('"props":[', ('"guards":[' + $guard + '],"props":['))
    function Get-GuardExportError([string]$Document) {
        [IO.File]::WriteAllText($path, $Document, [Text.UTF8Encoding]::new($false))
        try { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null }
        catch { return $_.Exception.Message }
        throw 'Guard export unexpectedly succeeded.'
    }
    [IO.File]::WriteAllText($path, $validGuard, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'A valid guard and its overrides export unchanged.'
    [IO.File]::WriteAllText($path, $validGuard.Replace('"fireInterval":0.075', '"fireInterval":0.05'), [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'The minimum guard firing interval exports unchanged.'
    foreach ($invalid in @(
        @{ document = $validGuard.Replace('"weapon":"pistol"', '"weapon":"unknown"'); error = 'animation or weapon' },
        @{ document = $validGuard.Replace('"model":"models/player/group01/male_03.mdl"', '"model":"models/player/group03/male_03.mdl"'); error = 'citizen model' },
        @{ document = $validGuard.Replace('"shirt":"catalogue_fabric_shirt_blue_plain"', '"shirt":"catalogue_fabric_pants_black_plain"'); error = 'shirt finish' },
        @{ document = $validGuard.Replace('"range":1000', '"range":0'); error = 'range must be positive' },
        @{ document = $validGuard.Replace('"damage":25', '"damage":0'); error = 'damage is outside' },
        @{ document = $validGuard.Replace('"fireInterval":0.075', '"fireInterval":0.049'); error = 'fireInterval is outside' },
        @{ document = $validGuard.Replace('"spread":0', '"spread":-1'); error = 'spread is outside' },
        @{ document = $validGuard.Replace('"spread":0', '"spread":"0"'); error = 'spread must be a number' },
        @{ document = $validGuard.Replace('"position":{"x":1', '"position":{"x":"1"'); error = 'position x must be a number' },
        @{ document = $validGuard.Replace('"guardId":"guard_1"', '"guardId":"guard_1","unexpected":true'); error = 'unsupported field' },
        @{ document = $validGuard.Replace($guard, ($guard + ',' + $guard)); error = 'IDs must be valid and unique' }
    )) {
        $problem = Get-GuardExportError $invalid.document
        Assert-Prefab ($problem -like "*$($invalid.error)*") "Guard validation reports $($invalid.error)."
    }

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
    $light = '{"lightId":"light_1","position":{"x":1,"y":2,"z":3},"angles":{"p":40,"y":45,"r":0},"color":{"r":255,"g":235,"b":200},"brightness":6,"fov":60,"range":512}'
    $withLight = $json.Replace('"props":[', ('"lights":[' + $light + '],"props":['))
    [IO.File]::WriteAllText($path, $withLight, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Valid spotlight exports unchanged.'
    foreach ($invalid in @(
        $withLight.Replace('"fov":60', '"fov":180'),
        $withLight.Replace('"range":512', '"range":8'),
        $withLight.Replace('"range":512', '"range":1000001'),
        $withLight.Replace('"brightness":6', '"brightness":-1'),
        $withLight.Replace('"brightness":6', '"brightness":1000001'),
        $withLight.Replace('"r":255', '"r":256'),
        $withLight.Replace($light, ($light + ',' + $light)),
        $withLight.Replace('"lights":[', '"lights":null,"unused":[')
    )) {
        [IO.File]::WriteAllText($path, $invalid, [Text.UTF8Encoding]::new($false))
        Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Invalid spotlight does not export.'
    }
    $particle = '{"particleId":"steam_1","effect":"steam","position":{"x":1,"y":2,"z":3},"angles":{"p":0,"y":90,"r":0},"mode":"triggered","overlap":false}'
    $withParticle = $json.Replace('"props":[', ('"particles":[' + $particle + '],"props":['))
    [IO.File]::WriteAllText($path, $withParticle, [Text.UTF8Encoding]::new($false))
    & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace | Out-Null
    Assert-Prefab ((Get-FileHash -LiteralPath $path).Hash -eq (Get-FileHash -LiteralPath $destination).Hash) 'Valid particle exports unchanged.'
    foreach ($invalid in @(
        $withParticle.Replace('"effect":"steam"', '"effect":"unknown"'),
        $withParticle.Replace('"mode":"triggered"', '"mode":"unknown"'),
        $withParticle.Replace('"overlap":false', '"overlap":"false"'),
        $withParticle.Replace($particle, ($particle + ',' + $particle))
    )) {
        [IO.File]::WriteAllText($path, $invalid, [Text.UTF8Encoding]::new($false))
        Assert-Rejected { & $exporter -Id 'roadblock' -SourceDirectory $source -OutputDirectory $output -Apply -Replace } 'Invalid particle does not export.'
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
