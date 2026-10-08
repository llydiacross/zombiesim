param([string]$StagedDirectory = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'workshop_packages.psm1') -Force
$passed = 0
function Assert-Package([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Workshop regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Assert-Rejected([string]$Name, [scriptblock]$Action) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Package $Name $rejected
}
foreach ($path in '..\secret.txt', 'materials\..\secret.txt', 'C:\secret.txt', '\root.txt',
    'materials\\bad.vtf', 'materials\.\bad.vtf', 'materials\bad:stream.vtf') {
    Assert-Rejected "reject unsafe path: $path" { ConvertTo-WorkshopPath $path }
}
Assert-Package 'canonical paths keep spaces and normalize case' ((ConvertTo-WorkshopPath 'SOUND\music\City 1.mp3') -eq 'sound/music/city 1.mp3')
$pending = Resolve-WorkshopId 'pending:core' 'core'
Assert-Package 'temporary identifier never becomes a Steam ID' ($pending.id -eq '' -and $pending.placeholder -eq 'pending:core')
Assert-Package 'missing ID gets explicit pending label' ((Resolve-WorkshopId '' 'world-03').placeholder -eq 'pending:world-03')
Assert-Package 'published ID retained as exact string' ((Resolve-WorkshopId '12345678901234567' 'core').id -eq '12345678901234567')
Assert-Rejected 'wrong package placeholder rejected' { Resolve-WorkshopId 'pending:world-01' 'core' }
Assert-Rejected 'zero is not a fake Workshop ID' { Resolve-WorkshopId '0' 'core' }
$files = @(
    [pscustomobject]@{ path = 'a.vtf'; group = 'a'; family = 'clothing'; bytes = 60 },
    [pscustomobject]@{ path = 'a.vmt'; group = 'a'; family = 'clothing'; bytes = 10 },
    [pscustomobject]@{ path = 'b.vtf'; group = 'b'; family = 'clothing'; bytes = 30 },
    [pscustomobject]@{ path = 'c.vtf'; group = 'c'; family = 'clothing'; bytes = 1 },
    [pscustomobject]@{ path = 'x.lua'; group = 'code'; family = 'core'; bytes = 10 }
)
$packs = @(Split-WorkshopPackages $files 100)
Assert-Package 'exact byte threshold fills first shard, one byte excess starts second' (
    $packs.Count -eq 3 -and $packs[0].id -eq 'clothing-01' -and $packs[0].bytes -eq 100 -and $packs[1].bytes -eq 1)
Assert-Package 'VTF/VMT companions stay together' (@($packs[0].files | Where-Object group -eq 'a').Count -eq 2)
$reversed = @($files)
[array]::Reverse($reversed)
Assert-Package 'sharding independent of enumeration order' (
    ($packs | ConvertTo-Json -Depth 6 -Compress) -eq ((Split-WorkshopPackages $reversed 100) | ConvertTo-Json -Depth 6 -Compress))
Assert-Rejected 'oversized indivisible group fails, not silently split' { Split-WorkshopPackages $files 69 }
Assert-Rejected 'invalid budget fails' { Split-WorkshopPackages $files 0 }
Assert-Rejected 'core never splits' {
    Split-WorkshopPackages @(
        [pscustomobject]@{ path = 'x'; group = 'a'; family = 'core'; bytes = 60 },
        [pscustomobject]@{ path = 'y'; group = 'b'; family = 'core'; bytes = 60 }) 100
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zombiesim-workshop-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $source = Join-Path $temporary 'source.txt'
    [IO.File]::WriteAllText($source, 'fixture', [Text.UTF8Encoding]::new($false))
    $inventory = @{}
    Add-WorkshopFile $inventory $source 'materials/fixture.vmt' 'common' 'fixture'
    Assert-Package 'inventory records exact bytes and SHA256' (
        $inventory['materials/fixture.vmt'].bytes -eq 7 -and $inventory['materials/fixture.vmt'].sha256.Length -eq 64)
    Assert-Rejected 'same virtual path twice fails even with same source' {
        Add-WorkshopFile $inventory $source 'Materials\fixture.vmt' 'common' 'fixture'
    }
    Assert-Rejected 'missing input fails explicitly' { Add-WorkshopFile $inventory "$source.missing" 'a.json' 'core' 'a' }
    Add-WorkshopFile $inventory $source 'data_static/music.json' 'core' 'music' '{"file":"sound/music/a.mp3"}'
    Assert-Package 'transformed text has independent output hash' (
        $inventory['data_static/music.json'].sha256 -ne $inventory['data_static/music.json'].sourceHash)
    $stage = Join-Path $temporary 'stage'
    foreach ($entry in $inventory.Values) {
        $destination = Join-Path $stage $entry.path.Replace('/', '\')
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        if ($null -ne $entry.text) { [IO.File]::WriteAllText($destination, $entry.text, [Text.UTF8Encoding]::new($false)) }
        else { Copy-Item -LiteralPath $entry.source -Destination $destination }
    }
    Test-WorkshopStaging $stage @($inventory.Values)
    Assert-Package 'staging verifies every file hash and size' $true
    [IO.File]::WriteAllText((Join-Path $stage 'materials\fixture.vmt'), 'fixturX')
    Assert-Rejected 'same-length staging corruption is detected' { Test-WorkshopStaging $stage @($inventory.Values) }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage 'materials\fixture.vmt') -Force
    [IO.File]::WriteAllText((Join-Path $stage 'unexpected.txt'), 'unowned')
    Assert-Rejected 'unowned staging extras fail' { Test-WorkshopStaging $stage @($inventory.Values) }
    Remove-Item -LiteralPath (Join-Path $stage 'unexpected.txt')
    $metadata = Join-Path $stage 'addon.json'
    Write-WorkshopJson $metadata @{ title = 'ZombieSim packaging fixture'; type = 'ServerContent'; tags = @('roleplay'); ignore = @() }
    $allFiles = @($inventory.Values) + @([pscustomobject]@{
        path = 'addon.json'; bytes = (Get-Item -LiteralPath $metadata).Length; sha256 = (Get-FileHash -LiteralPath $metadata).Hash.ToLowerInvariant() })
    $gameRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    $gmad = Join-Path $gameRoot 'bin\win64\gmad.exe'
    if (-not (Test-Path -LiteralPath $gmad)) { $gmad = Join-Path $gameRoot 'bin\gmad.exe' }
    Invoke-WorkshopArchive $gmad $stage (Join-Path $temporary 'fixture.gma') $allFiles 1MB
    Assert-Package 'bundled gmad round-trip preserves exact payload bytes and paths' $true
    $modelRoot = Join-Path $temporary 'models\zombiesim'
    $null = New-Item -ItemType Directory -Force -Path $modelRoot
    [IO.File]::WriteAllText((Join-Path $modelRoot 'fixture.mdl'), 'model')
    Assert-Rejected 'missing required model companions fail' { Get-WorkshopModelCompanions $temporary 'models/zombiesim/fixture.mdl' }
    foreach ($ext in '.vvd', '.dx90.vtx', '.phy') { [IO.File]::WriteAllText((Join-Path $modelRoot "fixture$ext"), 'companion') }
    Assert-Package 'required and optional model companions included' (@(Get-WorkshopModelCompanions $temporary 'models/zombiesim/fixture.mdl').Count -eq 4)
    Assert-Rejected 'mounted native assets never copied as owned models' { Get-WorkshopModelCompanions $temporary 'models/props_c17/native.mdl' }
    $fixtureRoot = Join-Path $temporary 'project'
    function Write-Fixture([string]$Path, [string]$Text) {
        $destination = Join-Path $fixtureRoot $Path
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        [IO.File]::WriteAllText($destination, $Text, [Text.UTF8Encoding]::new($false))
    }
    Write-Fixture 'gamemode\sh_distribution.lua' 'Distribution.Packaged = false'
    $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'entities')
    foreach ($name in 'icon24.png', 'logo.png') { Write-Fixture $name 'fixture' }
    Write-Fixture 'zombiesim.txt' '"zombiesim" { "workshopid" "15895" }'
    Write-Fixture 'content\data_static\clothing_catalogue.json' '{"schemaVersion":1,"releaseEligible":false,"files":["catalog_0000000000000000_shirt_male.vtf","catalog_0000000000000000_shirt_male.vmt"]}'
    Write-Fixture 'content\data_static\zombiesim_signs_preview.json' '{"variants":{}}'
    Write-Fixture 'content\data_static\music_definitions.json' '{"tracks":[{"id":"a","file":"sounds/music/a.mp3"}]}'
    Write-Fixture 'content\data_static\version.json' '{"schemaVersion":1,"product":"Z-Nation","stage":"Alpha","version":"9.8.7","status":"in development"}'
    Write-Fixture 'content\data_static\sky_catalogue.json' '{"schemaVersion":1,"ownedFiles":["materials\\zombiesim\\skies\\imported_fixtureft.vmt"],"ownedLicenceFiles":["data_static\\sky_licences\\imported_fixture\\README.txt"]}'
    Write-Fixture 'content\materials\zombiesim\skies\imported_fixtureft.vmt' 'owned sky material'
    Write-Fixture 'content\materials\zombiesim\skies\imported_tropo_night_1ft.vmt' 'retired sky material'
    Write-Fixture 'content\data_static\sky_licences\imported_fixture\README.txt' 'Artist licence fixture: retain this README.'
    Write-Fixture 'content\data_static\clothing_citizen_calibration.json' '{"schemaVersion":1,"previewOnly":false,"models":{}}'
    Write-Fixture 'content\sounds\music\a.mp3' 'audio'
    Write-Fixture 'content\sounds\music\preview skybox 1.mp3' 'launcher preview audio'
    Write-Fixture 'content\data_static\consolecommands.txt' 'development command'
    Write-Fixture 'content\maps\zz_dev_zoo.bsp' 'unreferenced development fixture'
    Write-Fixture 'content\materials\models\zombiesim\clothing\catalog_0000000000000000_shirt_male.vtf' 'vtf'
    Write-Fixture 'content\materials\models\zombiesim\clothing\catalog_0000000000000000_shirt_male.vmt' '"UnlitGeneric" {}'
    Write-Fixture 'content\materials\models\zombiesim\clothing\catalog_1111111111111111_orphan.vtf' 'orphan must survive'
    foreach ($name in 'prototype_blood_shirt_male', 'prototype_blood_shirt_female', 'prototype_blood_pants') {
        Write-Fixture "content\materials\models\zombiesim\clothing\$name.vtf" 'original blood'
        Write-Fixture "content\materials\models\zombiesim\clothing\$name.vmt" '"UnlitGeneric" {}'
    }
    foreach ($profile in 'city', 'preview') {
        $name = if ($profile -eq 'city') { 'zombiesim_world.json' } else { 'zombiesim_world_preview.json' }
        Write-WorkshopJson (Join-Path $fixtureRoot "content\data_static\$name") @{
            schemaVersion = 1; world = @{ profileId = $profile; mapDirectory = '' }
            cells = @(@{ map = "zz_${profile}_fixture" }); safeZones = @() }
        foreach ($ext in 'bsp', 'nav') { Write-Fixture "content\maps\zz_${profile}_fixture.$ext" $ext }
        Write-Fixture "content\maps\zn_${profile}_start.bsp" 'launcher'
        Write-Fixture "content\materials\worlds\$profile\cells\zz_${profile}_fixture.png" 'map image'
        Write-Fixture "content\materials\worlds\$profile\map_layers\all.png" 'world layer'
        $model = "models/zombiesim/skybox/cells/zz_${profile}_fixture_p0.mdl"
        Write-WorkshopJson (Join-Path $fixtureRoot "content\data_static\zombiesim_skybox_$profile.json") @{
            schemaVersion = 1; profile = $profile; recipes = @{ "zz_${profile}_fixture" = @($model) }
            snow = @{}; towers = @{}; detail = @{ models = @('models/props_c17/native.mdl'); recipes = @{} } }
        foreach ($ext in '.mdl', '.vvd', '.dx90.vtx') {
            Write-Fixture ($model.Replace('/', '\').Replace('.mdl', $ext).Insert(0, 'content\')) 'model'
        }
    }
    $fixtureSettings = Join-Path $fixtureRoot 'workshop-settings.json'
    Write-WorkshopJson $fixtureSettings @{
        schemaVersion = 1; worldProfiles = @('city', 'preview'); maximumShardBytes = 1MB; metadataReserveBytes = 65536
        releaseCleared = $false; coreWorkshopId = 'pending:core'; workshopIds = @{ 'clothing-01' = 'pending:clothing-01' }
        coreStaticFiles = @('clothing_catalogue.json', 'clothing_citizen_calibration.json', 'music_definitions.json', 'sky_catalogue.json', 'version.json', 'zombiesim_signs_preview.json')
        commonMaterialDirectories = @('materials\zombiesim\skies'); commonMaterialExtensions = @('.vmt', '.vtf', '.png'); externalDependencies = @('Mounted native fixtures') }
    $builder = Join-Path $PSScriptRoot 'build_workshop_packages.ps1'
    & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings -Pack
    $fixtureReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'generated\workshop\inventory-report.json') -Raw | ConvertFrom-Json
    Assert-Package 'full builder stages and round-trip packs both sandbox and city' (
        $fixtureReport.staged -and $fixtureReport.packed -and @($fixtureReport.profiles).Count -eq 2 -and
        @($fixtureReport.packages | Where-Object { -not $_.extractionVerified }).Count -eq 0)
    $bloodFiles = @($fixtureReport.packages.files | Where-Object path -like 'materials/models/zombiesim/clothing/prototype_blood_*')
    $bloodPacks = @($fixtureReport.packages | Where-Object {
        @($_.files | Where-Object path -like 'materials/models/zombiesim/clothing/prototype_blood_*').Count -gt 0
    })
    Assert-Package 'three shared blood overlays ship once with their companions in fixed clothing ownership' (
        $bloodFiles.Count -eq 6 -and @($bloodFiles.path | Select-Object -Unique).Count -eq 6 -and
        $bloodPacks.Count -eq 1 -and $bloodPacks[0].id -like 'clothing-*')
    Assert-Package 'core owns the citizen transfer manifest exactly once' (
        @($fixtureReport.packages.files | Where-Object path -eq 'data_static/clothing_citizen_calibration.json').Count -eq 1 -and
        @($fixtureReport.packages | Where-Object id -eq 'core').files.path -contains 'data_static/clothing_citizen_calibration.json')
    $licencePack = @($fixtureReport.packages | Where-Object {
        $_.files.path -contains 'data_static/sky_licences/imported_fixture/readme.txt'
    })
    Assert-Package 'common content owns the original sky README exactly once' (
        $licencePack.Count -eq 1 -and $licencePack[0].id -like 'common-*')
    Assert-Package 'sky ownership excludes retired materials without deleting source files' (
        @($fixtureReport.packages.files | Where-Object path -eq 'materials/zombiesim/skies/imported_fixtureft.vmt').Count -eq 1 -and
        @($fixtureReport.packages.files | Where-Object path -like '*imported_tropo_night_1*').Count -eq 0 -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot 'content\materials\zombiesim\skies\imported_tropo_night_1ft.vmt')))
    Assert-Package 'sky README survives GMA staging unchanged' (
        (Get-Content -LiteralPath (Join-Path $fixtureReport.stageRoot "$($licencePack[0].id)\data_static\sky_licences\imported_fixture\readme.txt") -Raw) -eq
        'Artist licence fixture: retain this README.')
    $core = Join-Path $fixtureReport.stageRoot 'core'
    $fixtureManifest = Get-Content -LiteralPath (Join-Path $core 'data_static\zombiesim_distribution.json') -Raw | ConvertFrom-Json
    Assert-Package 'manifest keeps placeholders separate from actionable Workshop IDs' (
        @($fixtureManifest.packs | Where-Object workshopId -ne '').Count -eq 0 -and
        @($fixtureManifest.packs | Where-Object workshopIdPlaceholder -like 'pending:*').Count -eq $fixtureManifest.packs.Count)
    Assert-Package 'manifest and report carry the single-source game version' (
        $fixtureManifest.gameVersion -eq '9.8.7' -and $fixtureManifest.gameStage -eq 'Alpha' -and $fixtureReport.gameVersion -eq '9.8.7' -and
        @($fixtureReport.packages | Where-Object id -eq 'core').files.path -contains 'data_static/version.json' -and
        @($fixtureReport.blockers | Where-Object { $_ -like "*9.8.7*in development*" }).Count -eq 1)
    Assert-Package 'packaged bootstrap cannot silently bypass missing manifest' (
        (Get-Content -LiteralPath (Join-Path $core 'gamemodes\zombiesim\gamemode\sh_distribution.lua') -Raw) -eq 'Distribution.Packaged = true')
    Assert-Package 'obsolete hardcoded Workshop ID removed without changing source' (
        (Get-Content -LiteralPath (Join-Path $core 'gamemodes\zombiesim\zombiesim.txt') -Raw) -notmatch '15895' -and
        (Get-Content -LiteralPath (Join-Path $fixtureRoot 'zombiesim.txt') -Raw) -match '15895')
    $transformedMusic = Get-Content -LiteralPath (Join-Path $core 'data_static\music_definitions.json') -Raw | ConvertFrom-Json
    Assert-Package 'canonical sound root and registry agree in staged package' ($transformedMusic.tracks[0].file -eq 'sound/music/a.mp3')
    $previewAudio = @($fixtureReport.packages | ForEach-Object { $_.files } |
        Where-Object path -eq 'sound/music/preview skybox 1.mp3')
    Assert-Package 'launcher preview soundtrack ships at canonical sound root' ($previewAudio.Count -eq 1)
    Assert-Package 'unowned files and bridge input excluded but untouched' (
        @($fixtureReport.excluded | Where-Object path -like '*orphan*').Count -eq 1 -and
        @($fixtureReport.excluded | Where-Object path -like '*consolecommands*').Count -eq 1 -and
        (Get-Content -LiteralPath (Join-Path $fixtureRoot 'content\materials\models\zombiesim\clothing\catalog_1111111111111111_orphan.vtf') -Raw) -eq 'orphan must survive')
    Assert-Package 'preview launcher is a required shipped asset, not a zoo' (
        @($fixtureReport.packages.files | Where-Object path -eq 'maps/zn_preview_start.bsp').Count -eq 1 -and
        @($fixtureReport.excluded | Where-Object path -eq 'maps/zz_dev_zoo.bsp').Count -eq 1)
    Assert-Package 'core owns both launchers so missing world packs can be diagnosed before deployment' (
        @($fixtureReport.packages | Where-Object id -eq 'core').files.path -contains 'maps/zn_preview_start.bsp' -and
        @($fixtureReport.packages | Where-Object id -eq 'core').files.path -contains 'maps/zn_city_start.bsp')
    $firstRelease = $fixtureReport.releaseId
    & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings
    $secondReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'generated\workshop\inventory-report.json') -Raw | ConvertFrom-Json
    Assert-Package 'same inputs reproduce release identity and shard ownership' ($secondReport.releaseId -eq $firstRelease)
    Assert-Rejected 'release gate rejects uncleared rights and unassigned IDs' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings -Release }
    $releaseReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'generated\workshop\inventory-report.json') -Raw | ConvertFrom-Json
    Assert-Package 'development and release manifests never share an output identity' ($releaseReport.releaseId -ne $firstRelease)
    Assert-Rejected 'existing staging never overwritten or deleted' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings -Stage }
    $originalClothing = Get-Content -LiteralPath (Join-Path $fixtureReport.stageRoot 'clothing-01\data_static\zombiesim_packages\clothing-01.json') -Raw
    Write-Fixture 'gamemode\sh_distribution.lua' "Distribution.Packaged = false`n// core-only update"
    & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings -Stage
    $updated = Get-Content -LiteralPath (Join-Path $fixtureRoot 'generated\workshop\inventory-report.json') -Raw | ConvertFrom-Json
    $updatedClothing = Get-Content -LiteralPath (Join-Path $updated.stageRoot 'clothing-01\data_static\zombiesim_packages\clothing-01.json') -Raw
    Assert-Package 'core-only update leaves content marker byte-identical for independent addon updates' (
        $updated.releaseId -ne $firstRelease -and $updatedClothing -eq $originalClothing)
    $assignedSettings = Get-Content -LiteralPath $fixtureSettings -Raw | ConvertFrom-Json
    $assignedSettings.releaseCleared = $true
    $assignedSettings.coreWorkshopId = '123456'
    $assignedSettings.workshopIds = @{ 'common-01' = '123457'; 'clothing-01' = '123458'; 'world-01' = '123459' }
    Write-WorkshopJson $fixtureSettings $assignedSettings
    $assignedCataloguePath = Join-Path $fixtureRoot 'content\data_static\clothing_catalogue.json'
    $assignedCatalogue = Get-Content -LiteralPath $assignedCataloguePath -Raw | ConvertFrom-Json
    $assignedCatalogue.releaseEligible = $true
    Write-WorkshopJson $assignedCataloguePath $assignedCatalogue
    Write-Fixture 'content\data_static\version.json' '{"schemaVersion":1,"product":"Z-Nation","stage":"Alpha","version":"9.8.7","status":"released"}'
    & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings -Release -Stage
    $assignedReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'generated\workshop\inventory-report.json') -Raw | ConvertFrom-Json
    $assignedCore = Join-Path $assignedReport.stageRoot 'core'
    $assignedManifest = Get-Content -LiteralPath (Join-Path $assignedCore 'data_static\zombiesim_distribution.json') -Raw | ConvertFrom-Json
    Assert-Package 'real assigned IDs replace all placeholders in release manifest' (
        $assignedReport.releaseEligible -and -not $assignedManifest.development -and
        @($assignedManifest.packs | Where-Object workshopId -eq '').Count -eq 0 -and
        @($assignedManifest.packs | Where-Object workshopIdPlaceholder -ne '').Count -eq 0)
    Assert-Package 'core bootstrap descriptor embeds the privately reserved real ID' (
        (Get-Content -LiteralPath (Join-Path $assignedCore 'gamemodes\zombiesim\zombiesim.txt') -Raw) -match '"workshopid"\s*"123456"')
    $expandedWorldPath = Join-Path $fixtureRoot 'content\data_static\zombiesim_world_preview.json'
    $expandedSkyPath = Join-Path $fixtureRoot 'content\data_static\zombiesim_skybox_preview.json'
    $worldFixture = Get-Content -Raw $expandedWorldPath | ConvertFrom-Json
    $skyFixture = Get-Content -Raw $expandedSkyPath | ConvertFrom-Json
    $fixtureBounds = @{revision = 2; tileSize = 640; coreTileGridSize = 5; coreHalfExtent = 1600;
        traversableHalfExtent = 2240; visualHalfExtent = 2880; neighbourPitch = 5760;
        coastContactHalfExtent = 2240; playableCeiling = 4608}
    $worldFixture.world | Add-Member cellBounds $fixtureBounds
    $worldFixture.world | Add-Member templatePlanSha256 ('a' * 64)
    $worldFixture.cells[0] | Add-Member waterSides @('N', 'W')
    Write-WorkshopJson $expandedWorldPath $worldFixture
    Assert-Rejected 'expanded world cannot package a legacy skyline' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings }
    $skyFixture.schemaVersion = 2
    $skyFixture | Add-Member cellBounds $fixtureBounds
    $skyFixture | Add-Member cellSpan 5760
    $skyFixture | Add-Member templatePlanSha256 ('a' * 64)
    $skyFixture | Add-Member geometry @{zz_preview_fixture = @{waterSides = @('W', 'N');
        coastHalfExtent = 2240; visualHalfExtent = 2880; vmfSha256 = ('b' * 64)}}
    Write-WorkshopJson $expandedSkyPath $skyFixture
    & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings
    Assert-Package 'matching expanded skyline packages alongside legacy city' $?
    $skyFixture.templatePlanSha256 = 'c' * 64
    Write-WorkshopJson $expandedSkyPath $skyFixture
    Assert-Rejected 'expanded skyline rejects stale world plan' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings }
    $skyFixture.templatePlanSha256 = 'a' * 64
    $skyFixture.geometry.zz_preview_fixture.waterSides = @('N')
    Write-WorkshopJson $expandedSkyPath $skyFixture
    Assert-Rejected 'expanded skyline rejects wrong coast attachment' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings }
    $skyFixture.geometry.zz_preview_fixture.waterSides = @('N', 'W')
    Write-WorkshopJson $expandedSkyPath $skyFixture
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'content\maps\zz_preview_fixture.bsp')
    Assert-Rejected 'missing sandbox map fails before staging' { & $builder -ProjectRoot $fixtureRoot -SettingsPath $fixtureSettings }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
if ($StagedDirectory) {
    $StagedDirectory = (Resolve-Path -LiteralPath $StagedDirectory).Path
    $report = Get-Content -LiteralPath (Join-Path $StagedDirectory 'package-report.json') -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath (Join-Path $StagedDirectory 'core\data_static\zombiesim_distribution.json') -Raw | ConvertFrom-Json
    Assert-Package 'staged manifest agrees with report release' ($manifest.releaseId -eq $report.releaseId)
    $owners = @{}
    foreach ($package in $report.packages) {
        $directory = Join-Path $StagedDirectory $package.id
        Test-WorkshopStaging $directory (@($package.files) + @($package.metadataFiles))
        Assert-Package "hash verified $($package.id)" $true
        $bytes = (Get-ChildItem -LiteralPath $directory -Recurse -File | Measure-Object Length -Sum).Sum
        Assert-Package "actual byte budget including metadata $($package.id)" ($bytes -eq $package.stagedBytes -and $bytes -le $report.maximumShardBytes)
        $marker = Get-Content -LiteralPath (Join-Path $directory "data_static\zombiesim_packages\$($package.id).json") -Raw | ConvertFrom-Json
        $declaration = @($manifest.packs | Where-Object id -eq $package.id)[0]
        $compatible = $marker.revision -eq $declaration.revision
        if ($package.id -eq 'core') { $compatible = $compatible -and $marker.releaseId -eq $report.releaseId }
        Assert-Package "marker compatible $($package.id)" $compatible
        if ($report.packed) {
            $gma = Join-Path $StagedDirectory "$($package.id).gma"
            Assert-Package "packed bytes and hash $($package.id)" (
                $package.extractionVerified -and (Get-Item -LiteralPath $gma).Length -eq $package.packedBytes -and
                $package.packedBytes -le $report.maximumShardBytes -and
                (Get-FileHash -LiteralPath $gma).Hash.ToLowerInvariant() -eq $package.packedSha256)
        }
        foreach ($file in $package.files) {
            Assert-Package "unique owner $($file.path)" (-not $owners.ContainsKey($file.path))
            $owners[$file.path] = $package.id
        }
    }
    Assert-Package 'preview ships alongside city by default' ('preview' -in $report.profiles -and 'city' -in $report.profiles)
}
Write-Host "Workshop package checks: $passed passed."
