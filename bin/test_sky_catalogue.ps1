Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$content = Join-Path $root 'content'
$game = (Resolve-Path (Join-Path $root '..\..')).Path
$catalogue = Get-Content (Join-Path $content 'data_static\sky_catalogue.json') -Raw | ConvertFrom-Json
$passed = 0
function Assert-Sky([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Sky catalogue regression: $Message" }
    $script:passed++
}
Assert-Sky ($catalogue.schemaVersion -eq 1) 'published schema'
$sourceSettings = Get-Content (Join-Path $root 'assets\skybox\catalogue.json') -Raw | ConvertFrom-Json
$expectedIds = @($sourceSettings.entries | ForEach-Object { $_.id })
foreach ($collection in $sourceSettings.collections) {
    foreach ($family in $collection.families) {
        foreach ($index in 1..$family.count) { $expectedIds += $collection.idPrefix + $family.prefix + $index }
    }
}
$expectedIds = @($expectedIds | Where-Object { $_ -notin $sourceSettings.excludedEntries })
Assert-Sky ($expectedIds -notcontains 'imported_tropo_night_1') 'retired night sky excluded from source allowlist'
Assert-Sky (@($catalogue.entries | Where-Object id -EQ 'imported_tropo_night_1').Count -eq 0) 'retired night sky not published'
Assert-Sky ($catalogue.entries.Count -eq $expectedIds.Count) 'every allowlisted set is published'
Assert-Sky ($catalogue.ownedFiles.Count -eq $expectedIds.Count * 12) 'six texture/material pairs per set'
Assert-Sky ($catalogue.ownedLicenceFiles.Count -eq $expectedIds.Count) 'each set retains a standalone licence file'
$owned = @{}
foreach ($path in $catalogue.ownedFiles) {
    Assert-Sky ($path -match '^materials\\zombiesim\\skies\\imported_[a-z0-9_]+\.(vtf|vmt)$') "safe owned path: $path"
    Assert-Sky (-not $owned.ContainsKey($path)) "unique owned path: $path"
    $owned[$path] = $true
}
foreach ($entry in $catalogue.entries) {
    Assert-Sky ($entry.id -in $expectedIds) "published id is allowlisted: $($entry.id)"
    Assert-Sky ($catalogue.ownedLicenceFiles -contains $entry.licenceFile -and
        $entry.licenceFile -match '^data_static\\sky_licences\\imported_[a-z0-9_]+\\README\.txt$') "owned licence path: $($entry.id)"
    $licencePath = Join-Path $content $entry.licenceFile
    Assert-Sky ([IO.File]::ReadAllText($licencePath) -eq $entry.licence) "standalone licence matches metadata: $($entry.id)"
    Assert-Sky (-not [string]::IsNullOrWhiteSpace($entry.credit) -and
        -not [string]::IsNullOrWhiteSpace($entry.licence) -and
        -not [string]::IsNullOrWhiteSpace($entry.permission)) "retained attribution/permission: $($entry.id)"
    Assert-Sky ($entry.context -in @('day', 'dusk', 'night', 'overcast')) "valid context: $($entry.id)"
    foreach ($suffix in 'ft', 'bk', 'lf', 'rt', 'up', 'dn') {
        $info = $entry.faces.$suffix
        $source = Join-Path (Join-Path $root 'assets\skybox') $info.source
        $relative = 'materials\' + ($entry.material -replace '/', '\') + $suffix
        $vtf = Join-Path $content ($relative + '.vtf')
        Assert-Sky ((Get-FileHash $vtf).Hash.ToLowerInvariant() -eq $info.sha256 -and
            (Get-FileHash $source).Hash -eq (Get-FileHash $vtf).Hash) "source textures preserved byte-for-byte: $relative"
        Assert-Sky ($info.width * $info.scaleX -eq $info.height * $info.scaleY) "authored square projection: $relative"
        $text = Get-Content (Join-Path $content ($relative + '.vmt')) -Raw
        Assert-Sky ($text.Contains('"$basetexture" "' + $entry.material + $suffix + '"')) "namespaced material reference: $relative"
        Assert-Sky ([string]::IsNullOrEmpty($info.transform) -or $text.Contains($info.transform)) "authored transform retained: $relative"
        foreach ($extension in 'vtf', 'vmt') {
            Assert-Sky ((Get-FileHash (Join-Path $content ($relative + '.' + $extension))).Hash -eq
                (Get-FileHash (Join-Path $game ($relative + '.' + $extension))).Hash) "installed copy matches: $relative.$extension"
        }
    }
}
$settings = Get-Content (Join-Path $root 'workshop-settings.json') -Raw | ConvertFrom-Json
Assert-Sky ($settings.coreStaticFiles -contains 'sky_catalogue.json') 'core ships licence/catalogue metadata'
Assert-Sky ($settings.commonMaterialDirectories -contains 'materials\zombiesim') 'common pack owns sky textures'
foreach ($id in $expectedIds) {
    Assert-Sky (@($catalogue.entries | Where-Object id -EQ $id).Count -eq 1) "allowlisted set published exactly once: $id"
}
Assert-Sky (@($catalogue.entries | Where-Object id -Match '^imported_ut').Count -eq 0) 'removed UT imports not staged'
Write-Host "$passed sky catalogue assertions passed."
