Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$builder = Join-Path $root 'bin\build_calling_cards.ps1'
Import-Module (Join-Path $root 'bin\calling_cards.psm1') -Force -DisableNameChecking
$passed = 0

function Assert-Card([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Calling-card regression: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}

function Assert-CardRejected([string]$Name, [string]$Message, [scriptblock]$Action) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $rejected = $true
    }
    Assert-Card $Name $rejected
}

function Write-CardJson([string]$Path, [object]$Data) {
    [IO.File]::WriteAllText($Path, ($Data | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
}

function Write-FixturePng([string]$Path, [int]$Width, [int]$Height, [Drawing.Color]$Color) {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    $image = [Drawing.Bitmap]::new($Width, $Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear($Color)
        $image.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $image.Dispose() }
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zombiesim-callingcards-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $source = Join-Path $temporary 'source'
    $content = Join-Path $temporary 'content'
    $null = New-Item -ItemType Directory -Path $source
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $content 'data_static')
    Write-FixturePng (Join-Path $content 'materials\scoreboard\backgrounds\default.png') 12 2 ([Drawing.Color]::Black)
    Write-FixturePng (Join-Path $content 'materials\scoreboard\details\default.png') 12 2 ([Drawing.Color]::Transparent)
    Write-FixturePng (Join-Path $source 'custom_background.png') 18 3 ([Drawing.Color]::FromArgb(97, 40, 120, 200))
    Write-FixturePng (Join-Path $source 'custom_details.png') 12 2 ([Drawing.Color]::FromArgb(71, 240, 80, 20))
    Write-FixturePng (Join-Path $source 'cover.png') 6 1 ([Drawing.Color]::White)
    Write-FixturePng (Join-Path $source 'mark.png') 2 2 ([Drawing.Color]::White)
    $config = @{
        schemaVersion = 1
        aliases = @{ background_old = 'background_custom' }
        shopPrices = @{ background_custom = 125; detail_mark = 500 }
        questRewards = @{ detail_mark = $true }
        recipes = @(
            @{
                category = 'background'
                layers = @(@{ image = 'cover.png'; mode = 'cover'; color = 'primary' })
                outputs = @(
                    @{ id = 'background_blue'; name = 'Blue'; colors = @{ primary = '#0040ff' } },
                    @{ id = 'background_green'; name = 'Green'; colors = @{ primary = '#00ff00' } }
                )
            },
            @{
                category = 'detail'
                layers = @(@{ image = 'mark.png'; mode = 'repeat'; color = '#ff0000'; opacity = 0.5;
                    scale = 1; spacingX = 2; spacingY = 2; offsetX = 0; offsetY = 0 })
                outputs = @(@{ id = 'detail_mark'; name = 'Red mark' })
            }
        )
    }
    $recipePath = Join-Path $source 'recipes.json'
    Write-CardJson $recipePath $config
    $plan = Get-CallingCardPlan $source $content 3
    Assert-Card 'both suffixes are discovered as separate categories' (
        $plan.finished.Count -eq 2 -and @($plan.finished.id | Sort-Object) -join ',' -eq 'background_custom,detail_custom')
    Assert-Card 'referenced non-card images are ingredients and variants are explicit' ($plan.generated.Count -eq 3)
    Assert-Card 'the two existing defaults remain built in' (
        $plan.builtins.Count -eq 2 -and $plan.builtins[0].material -eq 'scoreboard/backgrounds/default.png' -and
        $plan.builtins[1].material -eq 'scoreboard/details/default.png')
    Assert-CardRejected 'generated ceiling rejects the complete batch rather than truncating it' 'exceeds the approved' {
        Get-CallingCardPlan $source $content 2
    }
    $planOnlyOutput = Join-Path $temporary 'plan-only'
    & $builder -SourceDirectory $source -DefaultsRoot $content -OutputDirectory $planOnlyOutput -MaximumGenerated 3 -PlanOnly
    Assert-Card 'plan-only does not create preview output' (-not (Test-Path -LiteralPath $planOnlyOutput))
    $buildA = Build-CallingCardPreview $plan (Join-Path $temporary 'build-a')
    $buildB = Build-CallingCardPreview $plan (Join-Path $temporary 'build-b')
    $catalogueA = Get-Content -LiteralPath $buildA.catalogue -Raw | ConvertFrom-Json
    $catalogueB = Get-Content -LiteralPath $buildB.catalogue -Raw | ConvertFrom-Json
    Assert-Card 'all defaults, finished cards and named variants enter the catalogue' ($catalogueA.cards.Count -eq 7)
    Assert-Card 'rename aliases are retained in the catalogue' ($catalogueA.aliases.background_old -eq 'background_custom')
    Assert-Card 'finished and generated shop prices reach the catalogue' (
        @($catalogueA.cards | Where-Object { $_.id -eq 'background_custom' -and $_.shopCredits -eq 125 }).Count -eq 1 -and
        @($catalogueA.cards | Where-Object { $_.id -eq 'detail_mark' -and $_.shopCredits -eq 500 }).Count -eq 1)
    Assert-Card 'shop-only, quest-only and both acquisition modes are explicit' (
        @($catalogueA.cards | Where-Object { $_.id -eq 'background_custom' -and $_.questReward -eq $false }).Count -eq 1 -and
        @($catalogueA.cards | Where-Object { $_.id -eq 'background_blue' -and $_.questReward -eq $true -and
            $null -eq $_.PSObject.Properties['shopCredits'] }).Count -eq 1 -and
        @($catalogueA.cards | Where-Object { $_.id -eq 'detail_mark' -and $_.questReward -eq $true -and $_.shopCredits -eq 500 }).Count -eq 1)
    Assert-Card 'catalogue generation is byte deterministic' (
        (Get-FileHash -LiteralPath $buildA.catalogue).Hash -eq (Get-FileHash -LiteralPath $buildB.catalogue).Hash)
    foreach ($card in $catalogueA.cards | Where-Object { $_.source -ne 'builtin' }) {
        $pathA = Join-Path $buildA.directory ('materials\' + $card.material.Replace('/', '\'))
        $pathB = Join-Path $buildB.directory ('materials\' + $card.material.Replace('/', '\'))
        Assert-Card "deterministic bytes for $($card.id)" ((Get-FileHash -LiteralPath $pathA).Hash -eq (Get-FileHash -LiteralPath $pathB).Hash)
    }
    $originalRecipes = $config.recipes
    $originalOutputs = $config.recipes[0].outputs
    $config.recipes[0].outputs = @($originalOutputs[1], $originalOutputs[0])
    $config.recipes = @($originalRecipes[1], $originalRecipes[0])
    $unrelated = Join-Path $source 'unrelated_details.png'
    Write-FixturePng $unrelated 12 2 ([Drawing.Color]::Cyan)
    Write-CardJson $recipePath $config
    $reorderedPlan = Get-CallingCardPlan $source $content 3
    $reorderedBuild = Build-CallingCardPreview $reorderedPlan (Join-Path $temporary 'reordered')
    $reorderedCatalogue = Read-CardJson $reorderedBuild.catalogue
    $stable = $true
    foreach ($card in $catalogueA.cards) {
        $matchingCards = @($reorderedCatalogue.cards | Where-Object id -eq $card.id)
        if ($matchingCards.Count -ne 1 -or $matchingCards[0].name -cne $card.name -or
            $matchingCards[0].material -cne $card.material -or $matchingCards[0].bytes -ne $card.bytes -or
            $matchingCards[0].sha256 -cne $card.sha256) {
            $stable = $false
            break
        }
    }
    Assert-Card 'unrelated additions and recipe reordering preserve existing IDs, paths and bytes' (
        $stable -and $reorderedCatalogue.cards.Count -eq $catalogueA.cards.Count + 1)
    $config.recipes = $originalRecipes
    $config.recipes[0].outputs = $originalOutputs
    Remove-Item -LiteralPath $unrelated
    Write-CardJson $recipePath $config

    $stalePlan = Get-CallingCardPlan $source $content 3
    $coverPath = Join-Path $source 'cover.png'
    $coverBytes = [IO.File]::ReadAllBytes($coverPath)
    Write-FixturePng $coverPath 6 1 ([Drawing.Color]::Black)
    $staleOutput = Join-Path $temporary 'stale-ingredient'
    Assert-CardRejected 'ingredient changes after planning reject the build' 'ingredient changed during the build' {
        Build-CallingCardPreview $stalePlan $staleOutput
    }
    Assert-Card 'a rejected build removes its incomplete preview directory' (
        @(Get-ChildItem -LiteralPath $staleOutput -Directory -Force).Count -eq 0)
    [IO.File]::WriteAllBytes($coverPath, $coverBytes)

    foreach ($entry in @(
        @{ id = 'background_custom'; path = 'custom_background.png'; alpha = 97 },
        @{ id = 'detail_custom'; path = 'custom_details.png'; alpha = 71 }
    )) {
        $card = @($catalogueA.cards | Where-Object id -eq $entry.id)[0]
        $built = Join-Path $buildA.directory ('materials\' + $card.material.Replace('/', '\'))
        Assert-Card "finished $($entry.id) preserves original PNG bytes" (
            (Get-FileHash -LiteralPath $built).Hash -eq (Get-FileHash -LiteralPath (Join-Path $source $entry.path)).Hash)
        $bitmap = [Drawing.Bitmap]::new($built)
        try { Assert-Card "finished $($entry.id) preserves alpha" ($bitmap.GetPixel(0, 0).A -eq $entry.alpha) }
        finally { $bitmap.Dispose() }
    }
    $detail = @($catalogueA.cards | Where-Object id -eq 'detail_mark')[0]
    $detailImage = [Drawing.Bitmap]::new((Join-Path $buildA.directory ('materials\' + $detail.material.Replace('/', '\'))))
    try {
        $mark = $detailImage.GetPixel(0, 0)
        $gap = $detailImage.GetPixel(3, 3)
        Assert-Card 'generated image uses the required 750x125 dimensions' ($detailImage.Width -eq 750 -and $detailImage.Height -eq 125)
        Assert-Card 'repeat color and opacity apply while spacing remains transparent' (
            $mark.R -gt 240 -and $mark.G -lt 5 -and $mark.B -lt 5 -and $mark.A -ge 120 -and $mark.A -le 135 -and $gap.A -eq 0)
    } finally { $detailImage.Dispose() }
    $blue = @($catalogueA.cards | Where-Object id -eq 'background_blue')[0]
    $blueImage = [Drawing.Bitmap]::new((Join-Path $buildA.directory ('materials\' + $blue.material.Replace('/', '\'))))
    try {
        $pixel = $blueImage.GetPixel(749, 124)
        Assert-Card 'cover layer fills the canvas and applies the named variant color' (
            $pixel.A -eq 255 -and $pixel.R -lt 5 -and $pixel.G -ge 60 -and $pixel.G -le 68 -and $pixel.B -gt 245)
    } finally { $blueImage.Dispose() }
    $originalLayers = $config.recipes[0].layers
    $config.recipes[0].layers = @($originalLayers[0], @{ image = 'custom_background.png'; mode = 'cover'; opacity = 0.25 })
    $config.recipes[1].layers[0].scale = 2
    $config.recipes[1].layers[0].offsetX = 3
    $config.recipes[1].layers[0].offsetY = 3
    Write-CardJson $recipePath $config
    $layerPlan = Get-CallingCardPlan $source $content 3
    $layerBuild = Build-CallingCardPreview $layerPlan (Join-Path $temporary 'layer-controls')
    $layerCatalogue = Read-CardJson $layerBuild.catalogue
    $layerBlue = @($layerCatalogue.cards | Where-Object id -eq 'background_blue')[0]
    $layerBlueImage = [Drawing.Bitmap]::new((Join-Path $layerBuild.directory ('materials\' + $layerBlue.material.Replace('/', '\'))))
    try {
        Assert-Card 'a finished card can also be an ordered translucent recipe layer' (
            $layerPlan.finished.Count -eq 2 -and $layerBlueImage.GetPixel(200, 62).R -gt 0)
    } finally { $layerBlueImage.Dispose() }
    $layerDetail = @($layerCatalogue.cards | Where-Object id -eq 'detail_mark')[0]
    $layerDetailImage = [Drawing.Bitmap]::new((Join-Path $layerBuild.directory ('materials\' + $layerDetail.material.Replace('/', '\'))))
    try {
        Assert-Card 'repeat scale and XY offsets control actual pixels' (
            $layerDetailImage.GetPixel(4, 4).A -ge 120 -and $layerDetailImage.GetPixel(1, 1).A -eq 0)
    } finally { $layerDetailImage.Dispose() }
    $config.recipes[0].layers = $originalLayers
    $config.recipes[1].layers[0].scale = 1
    $config.recipes[1].layers[0].offsetX = 0
    $config.recipes[1].layers[0].offsetY = 0
    Write-CardJson $recipePath $config
    $budgetSource = Join-Path $temporary 'budget-source'
    $null = New-Item -ItemType Directory -Path $budgetSource
    $budgetOutputs = @(for ($number = 1; $number -le 512; $number++) {
        @{ id = ('background_test{0:000}' -f $number); name = "Test $number" }
    })
    $budgetRecipe = @{ schemaVersion = 1; aliases = @{}; recipes = @(@{
        category = 'background'; layers = @(); outputs = $budgetOutputs
    }) }
    $budgetPath = Join-Path $budgetSource 'recipes.json'
    Write-CardJson $budgetPath $budgetRecipe
    Assert-Card 'the approved 512-design boundary is planned without truncation' (
        (Get-CallingCardPlan $budgetSource $content 512).generated.Count -eq 512)
    $budgetRecipe.recipes[0].outputs += @{ id = 'background_extra'; name = 'Extra' }
    Write-CardJson $budgetPath $budgetRecipe
    Assert-CardRejected '513 generated designs exceed the first-review ceiling' 'exceeds the approved' {
        Get-CallingCardPlan $budgetSource $content 512
    }

    $defaultBackground = Join-Path $content 'materials\scoreboard\backgrounds\default.png'
    $defaultDetail = Join-Path $content 'materials\scoreboard\details\default.png'
    $defaultHashes = @((Get-FileHash -LiteralPath $defaultBackground).Hash, (Get-FileHash -LiteralPath $defaultDetail).Hash)
    $installedPath = Join-Path $content 'data_static\calling_cards.json'
    $stagedCustom = Join-Path $content 'materials\scoreboard\backgrounds\custom_background.png'
    $dryStage = Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content
    Assert-Card 'staging defaults to a non-writing plan' (
        -not $dryStage.applied -and $dryStage.changes.Count -eq 6 -and -not (Test-Path -LiteralPath $installedPath))
    Assert-CardRejected 'artwork staging requires explicit rights confirmation' 'rights' {
        Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply
    }
    Write-FixturePng $stagedCustom 12 2 ([Drawing.Color]::Purple)
    $unownedHash = (Get-FileHash -LiteralPath $stagedCustom).Hash
    Assert-CardRejected 'unowned material collisions cannot be overwritten' 'unowned' {
        Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply -RightsConfirmed
    }
    Assert-Card 'unowned material and absent catalogue survive the collision' (
        (Get-FileHash -LiteralPath $stagedCustom).Hash -eq $unownedHash -and -not (Test-Path -LiteralPath $installedPath))
    Remove-Item -LiteralPath $stagedCustom
    Assert-CardRejected 'a failure after initial catalogue publication rolls back all new files' 'previous files and catalogue restored' {
        Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply -RightsConfirmed `
            -AfterWrite { param($relative) if ($relative -eq 'data_static/calling_cards.json') { throw 'injected commit failure' } }
    }
    Assert-Card 'failed initial staging removes only its own new files' (
        -not (Test-Path -LiteralPath $installedPath) -and -not (Test-Path -LiteralPath $stagedCustom))
    $applied = Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply -RightsConfirmed
    Assert-Card 'validated images and catalogue are staged' ($applied.applied -and $applied.changes.Count -eq 6)
    $installed = Read-CardJson $installedPath
    Assert-CallingCardCatalogue $installed
    foreach ($card in $installed.cards) {
        $staged = Join-Path $content ('materials\' + $card.material.Replace('/', '\'))
        Assert-Card "staged $($card.id) matches its catalogue hash" (
            (Get-FileHash -LiteralPath $staged).Hash.ToLowerInvariant() -eq $card.sha256)
    }
    Assert-Card 'staging leaves both original defaults unchanged' (
        (Get-FileHash -LiteralPath $defaultBackground).Hash -eq $defaultHashes[0] -and
        (Get-FileHash -LiteralPath $defaultDetail).Hash -eq $defaultHashes[1])
    $again = Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply -RightsConfirmed
    Assert-Card 'repeated staging is idempotent' ($again.applied -and $again.changes.Count -eq 0)
    $originalCatalogueHash = (Get-FileHash -LiteralPath $installedPath).Hash
    $originalCustomHash = (Get-FileHash -LiteralPath $stagedCustom).Hash
    Write-FixturePng $stagedCustom 18 3 ([Drawing.Color]::Orange)
    Assert-CardRejected 'modified owned files block staging' 'changed or is corrupt' {
        Install-CallingCardBuild -BuildDirectory $buildA.directory -ContentRoot $content -Apply -RightsConfirmed
    }
    Assert-Card 'rejected staging keeps the old catalogue' ((Get-FileHash -LiteralPath $installedPath).Hash -eq $originalCatalogueHash)
    [IO.File]::Copy((Join-Path $source 'custom_background.png'), $stagedCustom, $true)

    Write-FixturePng (Join-Path $source 'custom_background.png') 18 3 ([Drawing.Color]::FromArgb(100, 8, 24, 48))
    $config.recipes[0].outputs[0].colors.primary = '#ff0000'
    Write-CardJson $recipePath $config
    $updatedPlan = Get-CallingCardPlan $source $content 3
    $updatedBuild = Build-CallingCardPreview $updatedPlan (Join-Path $temporary 'updated')
    $stagedBlue = Join-Path $content 'materials\scoreboard\backgrounds\generated_background_blue.png'
    $originalBlueHash = (Get-FileHash -LiteralPath $stagedBlue).Hash
    Assert-CardRejected 'mid-stage failures are surfaced after rollback' 'previous files and catalogue restored' {
        Install-CallingCardBuild -BuildDirectory $updatedBuild.directory -ContentRoot $content -Apply -RightsConfirmed `
            -AfterWrite { param($relative) throw "injected failure after $relative" }
    }
    Assert-Card 'rollback restores the exact former image and catalogue' (
        (Get-FileHash -LiteralPath $stagedCustom).Hash -eq $originalCustomHash -and
        (Get-FileHash -LiteralPath $stagedBlue).Hash -eq $originalBlueHash -and
        (Get-FileHash -LiteralPath $installedPath).Hash -eq $originalCatalogueHash)
    Assert-CardRejected 'a failure after replacing the catalogue rolls back every changed file' 'previous files and catalogue restored' {
        Install-CallingCardBuild -BuildDirectory $updatedBuild.directory -ContentRoot $content -Apply -RightsConfirmed `
            -AfterWrite { param($relative) if ($relative -eq 'data_static/calling_cards.json') { throw 'injected commit failure' } }
    }
    Assert-Card 'late rollback restores both old images and the old catalogue' (
        (Get-FileHash -LiteralPath $stagedCustom).Hash -eq $originalCustomHash -and
        (Get-FileHash -LiteralPath $stagedBlue).Hash -eq $originalBlueHash -and
        (Get-FileHash -LiteralPath $installedPath).Hash -eq $originalCatalogueHash)
    $recoveryFailure = $null
    try {
        Install-CallingCardBuild -BuildDirectory $updatedBuild.directory -ContentRoot $content -Apply -RightsConfirmed `
            -AfterWrite {
                param($relative)
                if ($relative -eq 'materials/scoreboard/backgrounds/generated_background_blue.png') {
                    [IO.File]::AppendAllText($stagedBlue, 'external change')
                    throw 'injected external modification'
                }
            } | Out-Null
    } catch { $recoveryFailure = $_.Exception.Message }
    Assert-Card 'an externally changed destination reports incomplete restoration' (
        $null -ne $recoveryFailure -and $recoveryFailure -like '*Restoration incomplete*Backups retained at*')
    $transactions = @(Get-ChildItem -LiteralPath (Join-Path $content 'data_static') -Directory -Force |
        Where-Object Name -like '.callingcards-stage-*')
    Assert-Card 'incomplete restoration retains one recovery journal' (
        $transactions.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $transactions[0].FullName 'journal.json')))
    $journal = Read-CardJson (Join-Path $transactions[0].FullName 'journal.json')
    $blueUpdate = @($journal | Where-Object relative -eq 'materials/scoreboard/backgrounds/generated_background_blue.png')
    Assert-Card 'the recovery journal retains the original verified backup' (
        $blueUpdate.Count -eq 1 -and (Test-Path -LiteralPath $blueUpdate[0].backup -PathType Leaf) -and
        [IO.Path]::GetDirectoryName($blueUpdate[0].backup) -eq $transactions[0].FullName -and
        (Get-FileHash -LiteralPath $blueUpdate[0].backup).Hash -eq $originalBlueHash)
    [IO.File]::Copy($blueUpdate[0].backup, $stagedBlue, $true)
    Remove-Item -LiteralPath $transactions[0].FullName -Recurse -Force
    Assert-Card 'fixture recovery restores the original material and catalogue' (
        (Get-FileHash -LiteralPath $stagedBlue).Hash -eq $originalBlueHash -and
        (Get-FileHash -LiteralPath $installedPath).Hash -eq $originalCatalogueHash)
    $update = Install-CallingCardBuild -BuildDirectory $updatedBuild.directory -ContentRoot $content -Apply -RightsConfirmed
    Assert-Card 'verified owned image updates can be installed' (
        $update.applied -and (Get-FileHash -LiteralPath $stagedCustom).Hash -ne $originalCustomHash)
    $saved = Join-Path $temporary 'saved-custom.png'
    Move-Item -LiteralPath (Join-Path $source 'custom_background.png') -Destination $saved
    $config.aliases = @{}
    Write-CardJson $recipePath $config
    Assert-CardRejected 'a price for a removed design is reported explicitly' 'active non-default card' {
        Get-CallingCardPlan $source $content 3
    }
    $config.shopPrices.Remove('background_custom')
    Write-CardJson $recipePath $config
    $removedPlan = Get-CallingCardPlan $source $content 3
    $removedBuild = Build-CallingCardPreview $removedPlan (Join-Path $temporary 'removed')
    $removed = Install-CallingCardBuild -BuildDirectory $removedBuild.directory -ContentRoot $content -Apply -RightsConfirmed
    $removedCatalogue = Read-CardJson $installedPath
    Assert-Card 'removed designs retain the owned file rather than pruning it' (
        $removed.retained -eq 1 -and (Test-Path -LiteralPath $stagedCustom) -and
        @($removedCatalogue.cards | Where-Object id -eq 'background_custom').Count -eq 0 -and
        @($removedCatalogue.ownedFiles | Where-Object material -eq 'scoreboard/backgrounds/custom_background.png').Count -eq 1)
    Move-Item -LiteralPath $saved -Destination (Join-Path $source 'custom_background.png')
    $config.aliases = @{ background_old = 'background_custom' }
    $config.shopPrices.background_custom = 125
    Write-CardJson $recipePath $config
    $restoredPlan = Get-CallingCardPlan $source $content 3
    $restoredBuild = Build-CallingCardPreview $restoredPlan (Join-Path $temporary 'restored')
    $restored = Install-CallingCardBuild -BuildDirectory $restoredBuild.directory -ContentRoot $content -Apply -RightsConfirmed
    Assert-Card 'a previously removed design can return using its stable owned path' (
        $restored.applied -and $restored.retained -eq 0 -and
        @((Read-CardJson $installedPath).cards | Where-Object id -eq 'background_custom').Count -eq 1)
    Assert-Card 'successful and rolled-back staging leave no transaction directories' (
        @(Get-ChildItem -LiteralPath (Join-Path $content 'data_static') -Directory -Force | Where-Object Name -like '.callingcards-stage-*').Count -eq 0)

    $unclassified = Join-Path $source 'stray.png'
    Write-FixturePng $unclassified 2 2 ([Drawing.Color]::White)
    Assert-CardRejected 'unclassified PNG fails visibly' 'Unclassified PNG' { Get-CallingCardPlan $source $content 3 }
    Remove-Item -LiteralPath $unclassified
    $duplicate = Join-Path $source 'custom-background_background.png'
    Write-FixturePng $duplicate 12 2 ([Drawing.Color]::White)
    $conflict = Join-Path $source 'custom_background_background.png'
    Write-FixturePng $conflict 12 2 ([Drawing.Color]::White)
    Assert-CardRejected 'normalization collisions are rejected' 'Conflicting finished-card' { Get-CallingCardPlan $source $content 3 }
    Remove-Item -LiteralPath $duplicate
    Remove-Item -LiteralPath $conflict
    $wrongRatio = Join-Path $source 'bad_details.png'
    Write-FixturePng $wrongRatio 10 2 ([Drawing.Color]::White)
    Assert-CardRejected 'non-6:1 finished images are rejected' '6:1 aspect ratio' { Get-CallingCardPlan $source $content 3 }
    Remove-Item -LiteralPath $wrongRatio
    $limitName = Join-Path $source (('a' * 120) + '_details.png')
    Write-FixturePng $limitName 12 2 ([Drawing.Color]::White)
    $limitPlan = Get-CallingCardPlan $source $content 3
    Assert-Card 'a finished-card display name of exactly 120 characters is accepted' (
        @($limitPlan.finished | Where-Object { $_.name.Length -eq 120 }).Count -eq 1)
    Remove-Item -LiteralPath $limitName
    $longName = Join-Path $source (('a' * 121) + '_details.png')
    Write-FixturePng $longName 12 2 ([Drawing.Color]::White)
    Assert-CardRejected 'overlong finished-card display names fail during planning' 'at most 120 characters' {
        Get-CallingCardPlan $source $content 3
    }
    Remove-Item -LiteralPath $longName
    foreach ($invalidPrice in @(0, -1, 1.5, 1000001, '125')) {
        $config.shopPrices.background_custom = $invalidPrice
        Write-CardJson $recipePath $config
        Assert-CardRejected "invalid shop price $invalidPrice fails during planning" 'Shop price' {
            Get-CallingCardPlan $source $content 3
        }
    }
    $config.shopPrices.background_custom = 125
    $config.shopPrices.background_default = 1
    Write-CardJson $recipePath $config
    Assert-CardRejected 'built-in defaults cannot be priced' 'active non-default card' {
        Get-CallingCardPlan $source $content 3
    }
    $config.shopPrices.Remove('background_default')
    $config.questRewards.background_missing = $true
    Write-CardJson $recipePath $config
    Assert-CardRejected 'quest eligibility cannot refer to an unavailable card' 'active non-default card' {
        Get-CallingCardPlan $source $content 3
    }
    $config.questRewards.Remove('background_missing')
    $config.questRewards.detail_default = $true
    Write-CardJson $recipePath $config
    Assert-CardRejected 'built-in defaults cannot have quest eligibility' 'active non-default card' {
        Get-CallingCardPlan $source $content 3
    }
    $config.questRewards.Remove('detail_default')
    $config.questRewards.background_custom = 'true'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'quest eligibility must be a boolean' 'must be true or false' {
        Get-CallingCardPlan $source $content 3
    }
    $config.questRewards.Remove('background_custom')
    $config.questRewards.background_blue = $false
    Write-CardJson $recipePath $config
    Assert-CardRejected 'a design needs at least one acquisition source' 'no acquisition source' {
        Get-CallingCardPlan $source $content 3
    }
    $config.questRewards.Remove('background_blue')
    $originalId = $config.recipes[0].outputs[0].id
    $config.recipes[0].outputs[0].id = 'background_' + ('a' * 188)
    Write-CardJson $recipePath $config
    $null = Get-CallingCardPlan $source $content 3
    Assert-Card 'a 199-character generated ID is accepted' $true
    $config.recipes[0].outputs[0].id = 'background_' + ('a' * 189)
    Write-CardJson $recipePath $config
    Assert-CardRejected 'overlong networked IDs fail during planning' 'at most 199 characters' {
        Get-CallingCardPlan $source $content 3
    }
    $config.recipes[0].outputs[0].id = $originalId
    $originalName = $config.recipes[0].outputs[0].name
    $config.recipes[0].outputs[0].name = 'Invalid' + [char]127 + 'Name'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'display names with control characters fail during planning' 'without control characters' {
        Get-CallingCardPlan $source $content 3
    }
    $config.recipes[0].outputs[0].name = $originalName
    $config.recipes[0].layers[0].image = '..\cover.png'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'ingredient traversal is rejected' 'relative PNG path' { Get-CallingCardPlan $source $content 3 }
    $config.recipes[0].layers[0].image = 'missing.png'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'missing ingredient is rejected' 'Missing recipe image' { Get-CallingCardPlan $source $content 3 }
    $config.recipes[0].layers[0].image = 'cover.png'
    $config.aliases.background_old = 'background_missing'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'dangling aliases do not silently fall back' 'unavailable card' { Get-CallingCardPlan $source $content 3 }
    $config.aliases.background_old = 'background_custom'
    $config.recipes[0].outputs[1].id = 'background_blue'
    Write-CardJson $recipePath $config
    Assert-CardRejected 'duplicate generated IDs are rejected' 'Duplicate or wrong-category' { Get-CallingCardPlan $source $content 3 }
    [IO.File]::WriteAllText($recipePath, '{"schemaVersion":1,"aliases":{},"recipes":[],"recipes":[]}')
    Assert-CardRejected 'duplicate JSON properties are rejected' 'Duplicate JSON field' { Get-CallingCardPlan $source $content 3 }
    [IO.File]::WriteAllText($recipePath, '{"schemaVersion":1,"aliases":{},"recipes":[],"\u0072ecipes":[]}')
    Assert-CardRejected 'escaped duplicate JSON properties are rejected' 'Duplicate JSON field' { Get-CallingCardPlan $source $content 3 }
    [IO.File]::WriteAllText($recipePath, '{"schemaVersion":1,"aliases":{},"recipes":[],"invalid":NaN}')
    Assert-CardRejected 'non-JSON numeric tokens are rejected' 'Invalid' { Get-CallingCardPlan $source $content 3 }
    [IO.File]::WriteAllText($recipePath, '{"schemaVersion":1,"aliases":{},"recipes":[],"invalid":"\q"}')
    Assert-CardRejected 'invalid JSON escapes are rejected' 'Invalid' { Get-CallingCardPlan $source $content 3 }
    [IO.File]::WriteAllText($recipePath, '{"schemaVersion":1,"aliases":{},"recipes":[],}')
    Assert-CardRejected 'trailing JSON commas are rejected' 'Invalid calling-card JSON' { Get-CallingCardPlan $source $content 3 }
    Assert-Card 'failed planning leaves the prior preview catalogue untouched' (
        (Get-FileHash -LiteralPath $buildA.catalogue).Hash -eq (Get-FileHash -LiteralPath $buildB.catalogue).Hash)
    Write-Host "Calling-card pipeline: $passed passed."
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
