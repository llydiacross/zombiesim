Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions

$script:CardWidth = 750
$script:CardHeight = 125
$script:Categories = @{
    background = @{ directory = 'backgrounds'; suffix = '_background' }
    detail = @{ directory = 'details'; suffix = '_details' }
}

function Get-CardField {
    param([object]$Object, [string]$Name, [object]$Default = $null, [switch]$Required)
    if ($Object -isnot [pscustomobject]) { throw "Expected an object while reading '$Name'." }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        if ($Required) { throw "Missing required field '$Name'." }
        return ,$Default
    }
    return ,$property.Value
}

function Read-CardJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Calling-card JSON is missing: $Path" }
    if (((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Calling-card JSON is a reparse point: $Path"
    }
    $text = [IO.File]::ReadAllText($Path)
    try {
        $validator = [Web.Script.Serialization.JavaScriptSerializer]::new()
        $validator.MaxJsonLength = [int]::MaxValue
        $null = $validator.DeserializeObject($text)
        $value = ConvertFrom-Json -InputObject $text
    }
    catch { throw "Invalid calling-card JSON '$Path': $($_.Exception.Message)" }
    $stack = [Collections.Generic.Stack[object]]::new()
    $tokens = [regex]::Matches($text, '(?s)"(?:\\.|[^"\\])*"|[{}\[\]:,]|[^{}\[\]:,\s]+')
    foreach ($match in $tokens) {
        $token = $match.Value
        if ($token -eq '{') {
            $stack.Push([pscustomobject]@{
                object = $true; awaitingKey = $true
                names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            })
        } elseif ($token -eq '[') {
            $stack.Push([pscustomobject]@{ object = $false; awaitingKey = $false; names = $null })
        } elseif ($token -eq '}' -or $token -eq ']') {
            if ($stack.Count -gt 0) { $null = $stack.Pop() }
        } elseif ($stack.Count -gt 0) {
            $frame = $stack.Peek()
            if ($frame.object -and $token -eq ',') {
                $frame.awaitingKey = $true
            } elseif ($frame.object -and $frame.awaitingKey -and $token.StartsWith('"')) {
                $name = ConvertFrom-Json -InputObject $token
                if (-not $frame.names.Add($name)) { throw "Duplicate JSON field '$name' in $Path." }
                $frame.awaitingKey = $false
            }
        }
        if ($token -notin @('{', '}', '[', ']', ':', ',') -and -not $token.StartsWith('"') -and
            $token -cnotmatch '^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?)$') {
            throw "Invalid JSON token '$token' in $Path."
        }
        if ($token.StartsWith('"') -and $token -cnotmatch '^"(?:\\["\\/bfnrt]|\\u[0-9a-fA-F]{4}|[^"\\\x00-\x1f])*"$') {
            throw "Invalid JSON string in $Path."
        }
    }
    return ,$value
}

function Assert-CardFields {
    param([object]$Object, [string[]]$Allowed, [string]$Location)
    if ($Object -isnot [pscustomobject]) { throw "$Location must be an object." }
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -cnotin $Allowed) { throw "Unknown field '$($property.Name)' in $Location." }
    }
}

function Assert-CardArray {
    param([object]$Value, [string]$Location)
    if ($Value -isnot [array]) { throw "$Location must be an array." }
}

function Get-CardNumber {
    param([object]$Value, [string]$Location, [double]$Minimum, [double]$Maximum, [switch]$Whole)
    if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and
        $Value -isnot [decimal] -and $Value -isnot [single]) { throw "$Location must be a number." }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum -or
        ($Whole -and $number -ne [math]::Floor($number))) {
        throw "$Location must be $(if ($Whole) { 'a whole number' } else { 'a finite number' }) from $Minimum to $Maximum."
    }
    return $number
}

function ConvertTo-CardColor {
    param([object]$Value, [string]$Location)
    if ($Value -isnot [string] -or $Value -cnotmatch '^#[a-fA-F0-9]{6}([a-fA-F0-9]{2})?$') {
        throw "$Location must be #RRGGBB or #RRGGBBAA."
    }
    $red = [Convert]::ToInt32($Value.Substring(1, 2), 16)
    $green = [Convert]::ToInt32($Value.Substring(3, 2), 16)
    $blue = [Convert]::ToInt32($Value.Substring(5, 2), 16)
    $alpha = if ($Value.Length -eq 9) { [Convert]::ToInt32($Value.Substring(7, 2), 16) } else { 255 }
    return [Drawing.Color]::FromArgb($alpha, $red, $green, $blue)
}

function Get-CardIdCategory {
    param([object]$Id, [string]$Location)
    if ($Id -isnot [string] -or $Id.Length -gt 199 -or $Id -cnotmatch '^(background|detail)_[a-z0-9]+(_[a-z0-9]+)*$') {
        throw "$Location must be a lowercase background_... or detail_... ID of at most 199 characters."
    }
    return $Matches[1]
}

function Assert-CardDisplayName {
    param([object]$Name, [string]$Location)
    if ($Name -isnot [string] -or $Name.Trim().Length -eq 0 -or $Name.Length -gt 120 -or
        $Name -match '[\x00-\x1f\x7f]') {
        throw "$Location needs a nonempty name of at most 120 characters without control characters."
    }
}

function Get-CardRelativePath {
    param([object]$Path, [string]$Location)
    if ($Path -isnot [string] -or $Path -notmatch '^[a-zA-Z0-9 _./\\-]+$' -or
        [IO.Path]::IsPathRooted($Path)) { throw "$Location is an unsafe source path." }
    $normalized = $Path.Replace('\', '/')
    if (@($normalized.Split('/') | Where-Object { $_ -in '', '.', '..' }).Count -ne 0 -or
        $normalized -notmatch '(?i)\.png$') { throw "$Location must be a relative PNG path without traversal." }
    return $normalized.ToLowerInvariant()
}

function Assert-CardAncestors {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Calling-card path contains a reparse point: $current"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-CardSourceFiles {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "Artist source directory is missing: $Directory" }
    $root = (Get-Item -LiteralPath $Directory).FullName.TrimEnd('\')
    Assert-CardAncestors $root
    $files = @{}
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $current -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Artist source contains a reparse point: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
            $relative = $item.FullName.Substring($root.Length + 1).Replace('\', '/')
            $key = $relative.ToLowerInvariant()
            if ($files.ContainsKey($key)) { throw "Conflicting artist source paths: $relative" }
            $files[$key] = $item.FullName
        }
    }
    return $files
}

function Get-CardImageInfo {
    param([string]$Path, [switch]$Finished)
    try { $image = [Drawing.Image]::FromFile($Path) }
    catch { throw "Unreadable PNG '$Path': $($_.Exception.Message)" }
    try {
        if ($image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or $image.Width -le 0 -or $image.Height -le 0) {
            throw "Not a valid PNG: $Path"
        }
        if ($Finished -and $image.Width -ne 6 * $image.Height) { throw "Finished card must have a 6:1 aspect ratio: $Path" }
        return [pscustomobject]@{
            width = $image.Width; height = $image.Height
            bytes = (Get-Item -LiteralPath $Path).Length
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } finally { $image.Dispose() }
}

function Assert-CardMaterial {
    param([object]$Material, [string]$Category, [string]$Location)
    $directory = $script:Categories[$Category].directory
    if ($Material -isnot [string] -or $Material -cnotmatch "^scoreboard/$directory/[a-z0-9][a-z0-9_ -]*\.png$") {
        throw "$Location is not a safe $Category scoreboard PNG path."
    }
}

function Assert-CardAliases {
    param([object]$Aliases, [hashtable]$Ids)
    if ($Aliases -isnot [pscustomobject] -and $Aliases -isnot [System.Collections.IDictionary]) {
        throw 'aliases must be an object.'
    }
    $map = @{}
    $properties = if ($Aliases -is [System.Collections.IDictionary]) {
        @($Aliases.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Aliases[$_] } })
    } else { @($Aliases.PSObject.Properties) }
    foreach ($entry in $properties) {
        $from = [string]$entry.Name
        $sourceCategory = Get-CardIdCategory $from 'Alias source'
        $targetCategory = Get-CardIdCategory $entry.Value "Alias target for $from"
        if ($sourceCategory -cne $targetCategory -or $Ids.ContainsKey($from) -or $map.ContainsKey($from)) {
            throw "Invalid or conflicting alias: $from -> $($entry.Value)"
        }
        $map[$from] = $entry.Value
    }
    foreach ($from in $map.Keys) {
        $visited = @{}
        $current = $from
        while ($map.ContainsKey($current)) {
            if ($visited.ContainsKey($current)) { throw "Calling-card alias cycle at $current." }
            $visited[$current] = $true
            $current = $map[$current]
        }
        if (-not $Ids.ContainsKey($current)) { throw "Alias '$from' points to an unavailable card '$current'." }
    }
}

function Get-CallingCardPlan {
    param([string]$SourceDirectory, [string]$DefaultsRoot, [int]$MaximumGenerated = 512)
    if ($MaximumGenerated -lt 0) { throw 'MaximumGenerated cannot be negative.' }
    $files = Get-CardSourceFiles $SourceDirectory
    if (-not $files.ContainsKey('recipes.json')) { throw 'Artist source must contain recipes.json.' }
    $settings = Read-CardJson $files['recipes.json']
    Assert-CardFields $settings @('schemaVersion', 'aliases', 'recipes', 'shopPrices', 'questRewards') 'recipes.json'
    if ((Get-CardField $settings 'schemaVersion' -Required) -ne 1) { throw 'Calling-card recipe schemaVersion must be 1.' }
    $aliases = Get-CardField $settings 'aliases' -Required
    $recipes = Get-CardField $settings 'recipes' -Required
    $shopPrices = Get-CardField $settings 'shopPrices' ([pscustomobject]@{})
    if ($shopPrices -isnot [pscustomobject]) { throw 'shopPrices must be an object.' }
    $questRewards = Get-CardField $settings 'questRewards' ([pscustomobject]@{})
    if ($questRewards -isnot [pscustomobject]) { throw 'questRewards must be an object.' }
    Assert-CardArray $recipes 'recipes'
    $referenced = @{}
    $generated = [Collections.Generic.List[object]]::new()
    $finished = [Collections.Generic.List[object]]::new()
    $ids = @{ background_default = $true; detail_default = $true }
    $materials = @{ 'scoreboard/backgrounds/default.png' = $true; 'scoreboard/details/default.png' = $true }

    foreach ($recipe in $recipes) {
        Assert-CardFields $recipe @('category', 'layers', 'outputs') 'recipe'
        $category = Get-CardField $recipe 'category' -Required
        if ($category -isnot [string] -or $category -cnotin @('background', 'detail')) { throw 'Recipe category must be background or detail.' }
        $layers = Get-CardField $recipe 'layers' -Required
        $outputs = Get-CardField $recipe 'outputs' -Required
        Assert-CardArray $layers 'recipe.layers'
        Assert-CardArray $outputs 'recipe.outputs'
        if ($outputs.Count -eq 0) { throw 'Every recipe needs at least one named output.' }
        $parsedLayers = [Collections.Generic.List[object]]::new()
        foreach ($layer in $layers) {
            Assert-CardFields $layer @('image', 'mode', 'color', 'opacity', 'scale', 'spacingX', 'spacingY', 'offsetX', 'offsetY') 'recipe layer'
            $imageKey = Get-CardRelativePath (Get-CardField $layer 'image' -Required) 'Layer image'
            if (-not $files.ContainsKey($imageKey)) { throw "Missing recipe image: $imageKey" }
            $referenced[$imageKey] = $true
            $info = Get-CardImageInfo $files[$imageKey]
            $mode = Get-CardField $layer 'mode' -Required
            if ($mode -cnotin @('cover', 'repeat')) { throw 'Layer mode must be cover or repeat.' }
            $color = Get-CardField $layer 'color' '#ffffffff'
            if ($color -isnot [string]) { throw 'Layer color must be a colour or named output colour.' }
            if ($color.StartsWith('#')) { $null = ConvertTo-CardColor $color 'Layer color' }
            elseif ($color -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid layer color name: $color" }
            $opacity = Get-CardNumber (Get-CardField $layer 'opacity' 1) 'Layer opacity' 0 1
            $scale = Get-CardNumber (Get-CardField $layer 'scale' 1) 'Layer scale' 0.0001 4096
            $spacingX = Get-CardNumber (Get-CardField $layer 'spacingX' 0) 'Layer spacingX' 0 8192 -Whole
            $spacingY = Get-CardNumber (Get-CardField $layer 'spacingY' 0) 'Layer spacingY' 0 8192 -Whole
            if ($mode -eq 'cover' -and ($spacingX -ne 0 -or $spacingY -ne 0)) { throw 'Spacing applies only to repeating layers.' }
            $offsetX = Get-CardNumber (Get-CardField $layer 'offsetX' 0) 'Layer offsetX' -1000000 1000000
            $offsetY = Get-CardNumber (Get-CardField $layer 'offsetY' 0) 'Layer offsetY' -1000000 1000000
            if ($mode -eq 'repeat') {
                $tileWidth = [math]::Max(1, [math]::Ceiling($info.width * $scale)) + $spacingX
                $tileHeight = [math]::Max(1, [math]::Ceiling($info.height * $scale)) + $spacingY
                if ($tileWidth -gt 8192 -or $tileHeight -gt 8192 -or $tileWidth * $tileHeight -gt 16777216) {
                    throw "Repeat tile exceeds the safe 8192-axis/16777216-pixel working limit: $imageKey"
                }
            }
            $parsedLayers.Add([pscustomobject]@{
                image = $files[$imageKey]; imageKey = $imageKey; sourceHash = $info.sha256
                mode = $mode; color = $color; opacity = $opacity; scale = $scale
                spacingX = $spacingX; spacingY = $spacingY; offsetX = $offsetX; offsetY = $offsetY
            })
        }
        foreach ($output in $outputs) {
            Assert-CardFields $output @('id', 'name', 'baseColor', 'colors') 'recipe output'
            $id = Get-CardField $output 'id' -Required
            if ((Get-CardIdCategory $id 'Recipe output ID') -cne $category -or $ids.ContainsKey($id)) {
                throw "Duplicate or wrong-category calling-card ID: $id"
            }
            $name = Get-CardField $output 'name' -Required
            Assert-CardDisplayName $name "Recipe output '$id'"
            $baseColor = Get-CardField $output 'baseColor' '#00000000'
            $null = ConvertTo-CardColor $baseColor "Base color for $id"
            $colors = Get-CardField $output 'colors' ([pscustomobject]@{})
            if ($colors -isnot [pscustomobject]) { throw "Output colors for $id must be an object." }
            foreach ($colorProperty in $colors.PSObject.Properties) {
                if ($colorProperty.Name -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid color name '$($colorProperty.Name)' in $id." }
                $null = ConvertTo-CardColor $colorProperty.Value "Color '$($colorProperty.Name)' for $id"
            }
            foreach ($layer in $parsedLayers) {
                if (-not $layer.color.StartsWith('#') -and $null -eq $colors.PSObject.Properties[$layer.color]) {
                    throw "Output '$id' does not define color '$($layer.color)'."
                }
            }
            $material = 'scoreboard/{0}/generated_{1}.png' -f $script:Categories[$category].directory, $id
            if ($materials.ContainsKey($material)) { throw "Conflicting output path: $material" }
            $ids[$id] = $true
            $materials[$material] = $true
            $generated.Add([pscustomobject]@{
                id = $id; name = $name; category = $category; source = 'generated'; material = $material
                baseColor = $baseColor; colors = $colors; layers = @($parsedLayers.ToArray())
            })
        }
    }
    if ($generated.Count -gt $MaximumGenerated) {
        throw "Generated design count $($generated.Count) exceeds the approved build limit of $MaximumGenerated; nothing was written."
    }

    $ignored = [Collections.Generic.List[string]]::new()
    [string[]]$keys = @($files.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    foreach ($key in $keys) {
        if ($key -eq 'recipes.json') { continue }
        if ($key -notmatch '\.png$') { $ignored.Add($key); continue }
        $filename = [IO.Path]::GetFileNameWithoutExtension($key)
        $category = $null
        foreach ($candidate in @('background', 'detail')) {
            if ($filename.EndsWith($script:Categories[$candidate].suffix, [StringComparison]::Ordinal)) { $category = $candidate; break }
        }
        if (-not $category) {
            if (-not $referenced.ContainsKey($key)) { throw "Unclassified PNG is not a referenced ingredient: $key" }
            continue
        }
        $stem = $filename.Substring(0, $filename.Length - $script:Categories[$category].suffix.Length)
        if ($stem -cnotmatch '^[a-z0-9]+([_ -][a-z0-9]+)*$') { throw "Invalid finished-card filename: $key" }
        $slug = [regex]::Replace($stem, '[_ -]+', '_')
        $id = "${category}_$slug"
        $null = Get-CardIdCategory $id 'Finished-card ID'
        $material = 'scoreboard/{0}/{1}.png' -f $script:Categories[$category].directory, $filename
        if ($ids.ContainsKey($id) -or $materials.ContainsKey($material)) { throw "Conflicting finished-card ID or output path: $key" }
        $info = Get-CardImageInfo $files[$key] -Finished
        $name = [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($slug.Replace('_', ' '))
        Assert-CardDisplayName $name "Finished card '$key'"
        $ids[$id] = $true
        $materials[$material] = $true
        $finished.Add([pscustomobject]@{
            id = $id; name = $name
            category = $category; source = 'finished'; material = $material
            sourcePath = $files[$key]; sourceHash = $info.sha256
        })
    }
    Assert-CardAliases $aliases $ids
    foreach ($price in $shopPrices.PSObject.Properties) {
        $null = Get-CardIdCategory $price.Name 'Shop price ID'
        if (-not $ids.ContainsKey($price.Name) -or $price.Name -cin @('background_default', 'detail_default')) {
            throw "Shop price must name an active non-default card: $($price.Name)"
        }
        $amount = Get-CardNumber $price.Value "Shop price for $($price.Name)" 1 1000000 -Whole
        $card = @($finished.ToArray()) + @($generated.ToArray()) | Where-Object { $_.id -ceq $price.Name }
        $card | Add-Member -NotePropertyName shopCredits -NotePropertyValue ([int]$amount)
    }
    foreach ($reward in $questRewards.PSObject.Properties) {
        $null = Get-CardIdCategory $reward.Name 'Quest reward ID'
        if (-not $ids.ContainsKey($reward.Name) -or $reward.Name -cin @('background_default', 'detail_default')) {
            throw "Quest reward must name an active non-default card: $($reward.Name)"
        }
        if ($reward.Value -isnot [bool]) { throw "Quest reward eligibility must be true or false: $($reward.Name)" }
    }
    foreach ($card in @($finished.ToArray()) + @($generated.ToArray())) {
        $hasPrice = $null -ne $card.PSObject.Properties['shopCredits']
        $reward = $questRewards.PSObject.Properties[$card.id]
        $eligible = if ($null -ne $reward) { $reward.Value } else { -not $hasPrice }
        if (-not $hasPrice -and -not $eligible) { throw "Card has no acquisition source: $($card.id)" }
        $card | Add-Member -NotePropertyName questReward -NotePropertyValue ([bool]$eligible)
    }
    $builtins = @(
        [pscustomobject][ordered]@{ id = 'background_default'; name = 'Default'; category = 'background'; source = 'builtin'; material = 'scoreboard/backgrounds/default.png' },
        [pscustomobject][ordered]@{ id = 'detail_default'; name = 'Default'; category = 'detail'; source = 'builtin'; material = 'scoreboard/details/default.png' }
    )
    foreach ($builtin in $builtins) {
        $path = Join-Path $DefaultsRoot ('materials\' + $builtin.material.Replace('/', '\'))
        $info = Get-CardImageInfo $path -Finished
        $builtin | Add-Member -NotePropertyName bytes -NotePropertyValue $info.bytes
        $builtin | Add-Member -NotePropertyName sha256 -NotePropertyValue $info.sha256
    }
    return [pscustomobject]@{
        builtins = $builtins; finished = @($finished.ToArray()); generated = @($generated.ToArray())
        aliases = $aliases; ignored = @($ignored.ToArray())
    }
}

function Assert-CallingCardCatalogue {
    param([object]$Catalogue)
    Assert-CardFields $Catalogue @('schemaVersion', 'cards', 'aliases', 'ownedFiles') 'calling-card catalogue'
    if ((Get-CardField $Catalogue 'schemaVersion' -Required) -ne 1) { throw 'Calling-card catalogue schemaVersion must be 1.' }
    $cards = Get-CardField $Catalogue 'cards' -Required
    $ownedFiles = Get-CardField $Catalogue 'ownedFiles' -Required
    $aliases = Get-CardField $Catalogue 'aliases' -Required
    Assert-CardArray $cards 'catalogue.cards'
    Assert-CardArray $ownedFiles 'catalogue.ownedFiles'
    $ids = @{}
    $materials = @{}
    $activeOwned = @{}
    foreach ($card in $cards) {
        Assert-CardFields $card @('id', 'name', 'category', 'source', 'material', 'bytes', 'sha256', 'shopCredits', 'questReward') 'catalogue card'
        $id = Get-CardField $card 'id' -Required
        $category = Get-CardIdCategory $id 'Catalogue card ID'
        if ((Get-CardField $card 'category' -Required) -cne $category -or $ids.ContainsKey($id)) {
            throw "Duplicate or wrong-category catalogue card: $id"
        }
        $name = Get-CardField $card 'name' -Required
        Assert-CardDisplayName $name "Catalogue card '$id'"
        $source = Get-CardField $card 'source' -Required
        if ($source -cnotin @('builtin', 'finished', 'generated')) { throw "Invalid catalogue source for $id." }
        if ($null -ne $card.PSObject.Properties['shopCredits']) {
            if ($source -eq 'builtin') { throw "Built-in card cannot have a shop price: $id" }
            $null = Get-CardNumber $card.shopCredits "Shop price for $id" 1 1000000 -Whole
        }
        $reward = $card.PSObject.Properties['questReward']
        if ($source -eq 'builtin') {
            if ($null -ne $reward) { throw "Built-in card cannot have quest eligibility: $id" }
        } elseif ($null -eq $reward -or $reward.Value -isnot [bool]) {
            throw "Card requires explicit boolean quest eligibility: $id"
        } elseif (-not $reward.Value -and $null -eq $card.PSObject.Properties['shopCredits']) {
            throw "Card has no acquisition source: $id"
        }
        $material = Get-CardField $card 'material' -Required
        Assert-CardMaterial $material $category "Material for $id"
        if ($materials.ContainsKey($material)) { throw "Duplicate catalogue material: $material" }
        $bytes = Get-CardNumber (Get-CardField $card 'bytes' -Required) "Byte count for $id" 1 ([long]::MaxValue) -Whole
        $hash = Get-CardField $card 'sha256' -Required
        if ($hash -isnot [string] -or $hash -cnotmatch '^[a-f0-9]{64}$') { throw "Invalid SHA-256 for $id." }
        $expectedDefault = 'scoreboard/{0}/default.png' -f $script:Categories[$category].directory
        if ($source -eq 'builtin') {
            if ($id -cne "${category}_default" -or $material -cne $expectedDefault) { throw "Invalid built-in card: $id" }
        } else {
            if ($id -ceq "${category}_default" -or $material -ceq $expectedDefault) { throw "Non-built-in card conflicts with the default: $id" }
            if ($source -eq 'generated' -and $material -cne ('scoreboard/{0}/generated_{1}.png' -f $script:Categories[$category].directory, $id)) {
                throw "Generated material does not match its ID: $id"
            }
            if ($source -eq 'finished' -and -not $material.EndsWith($script:Categories[$category].suffix + '.png', [StringComparison]::Ordinal)) {
                throw "Finished material has the wrong category suffix: $id"
            }
            $activeOwned[$material] = [pscustomobject]@{ bytes = $bytes; sha256 = $hash }
        }
        $ids[$id] = $true
        $materials[$material] = $true
    }
    foreach ($id in 'background_default', 'detail_default') {
        if (-not $ids.ContainsKey($id)) { throw "Catalogue is missing the built-in $id." }
    }
    $owned = @{}
    foreach ($entry in $ownedFiles) {
        Assert-CardFields $entry @('material', 'bytes', 'sha256') 'catalogue ownership entry'
        $material = Get-CardField $entry 'material' -Required
        if ($material -isnot [string] -or $material -cnotmatch '^scoreboard/(backgrounds|details)/') {
            throw 'Invalid catalogue ownership material.'
        }
        $category = if ($Matches[1] -eq 'backgrounds') { 'background' } else { 'detail' }
        Assert-CardMaterial $material $category 'Ownership material'
        if ($material -ceq ('scoreboard/{0}/default.png' -f $script:Categories[$category].directory) -or $owned.ContainsKey($material)) {
            throw "Duplicate or reserved ownership material: $material"
        }
        $bytes = Get-CardNumber (Get-CardField $entry 'bytes' -Required) "Owned byte count for $material" 1 ([long]::MaxValue) -Whole
        $hash = Get-CardField $entry 'sha256' -Required
        if ($hash -isnot [string] -or $hash -cnotmatch '^[a-f0-9]{64}$') { throw "Invalid owned SHA-256 for $material." }
        $owned[$material] = [pscustomobject]@{ bytes = $bytes; sha256 = $hash }
    }
    foreach ($material in $activeOwned.Keys) {
        if (-not $owned.ContainsKey($material) -or $owned[$material].sha256 -cne $activeOwned[$material].sha256 -or
            $owned[$material].bytes -ne $activeOwned[$material].bytes) { throw "Active card lacks matching ownership: $material" }
    }
    Assert-CardAliases $aliases $ids
}

function Get-CardSafePath {
    param([string]$Root, [string]$Relative)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Calling-card root directory is missing: $Root" }
    $rootItem = Get-Item -LiteralPath $Root
    Assert-CardAncestors $rootItem.FullName
    if ($Relative -notmatch '^[a-zA-Z0-9 _./-]+$' -or @($Relative.Split('/') | Where-Object { $_ -in '', '.', '..' }).Count -gt 0) {
        throw "Unsafe calling-card path: $Relative"
    }
    $current = $rootItem.FullName
    foreach ($part in $Relative.Split('/')) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Calling-card path contains a reparse point: $current" }
        }
    }
    return $current
}

function Get-CardFileDigest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Calling-card file is missing: $Path" }
    return [pscustomobject]@{
        bytes = (Get-Item -LiteralPath $Path).Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-CardFileDigest {
    param([string]$Path, [object]$Expected)
    $actual = Get-CardFileDigest $Path
    if ($actual.bytes -ne $Expected.bytes -or $actual.sha256 -cne $Expected.sha256) {
        throw "Calling-card file has changed or is corrupt: $Path"
    }
}

function Install-CallingCardBuild {
    param(
        [string]$BuildDirectory, [string]$ContentRoot, [switch]$Apply, [switch]$RightsConfirmed,
        [scriptblock]$AfterWrite
    )
    $previewPath = Get-CardSafePath $BuildDirectory 'calling_cards.json'
    $preview = Read-CardJson $previewPath
    Assert-CallingCardCatalogue $preview
    $destinationCatalogue = Get-CardSafePath $ContentRoot 'data_static/calling_cards.json'
    $previous = $null
    $previousCatalogueHash = $null
    if (Test-Path -LiteralPath $destinationCatalogue) {
        $previous = Read-CardJson $destinationCatalogue
        Assert-CallingCardCatalogue $previous
        $previousCatalogueHash = (Get-CardFileDigest $destinationCatalogue).sha256
    }
    $oldOwned = @{}
    if ($null -ne $previous) {
        foreach ($entry in $previous.ownedFiles) {
            $path = Get-CardSafePath $ContentRoot ('materials/' + $entry.material)
            Assert-CardFileDigest $path $entry
            $oldOwned[$entry.material] = $entry
        }
    }
    $active = @($preview.cards | Where-Object { $_.source -ne 'builtin' })
    if ($Apply -and $active.Count -gt 0 -and -not $RightsConfirmed) {
        throw 'Staging artwork requires explicit confirmation of rights for every finished image and recipe ingredient.'
    }
    $updates = [Collections.Generic.List[object]]::new()
    $mergedOwned = @{}
    foreach ($path in $oldOwned.Keys) { $mergedOwned[$path] = $oldOwned[$path] }
    foreach ($card in $preview.cards) {
        $relative = 'materials/' + $card.material
        $target = Get-CardSafePath $ContentRoot $relative
        if ($card.source -eq 'builtin') {
            Assert-CardFileDigest $target $card
            continue
        }
        $source = Get-CardSafePath $BuildDirectory $relative
        Assert-CardFileDigest $source $card
        $null = Get-CardImageInfo $source -Finished
        $beforeHash = $null
        if (Test-Path -LiteralPath $target) {
            if (-not $oldOwned.ContainsKey($card.material)) { throw "Refusing to overwrite an unowned calling-card file: $target" }
            $beforeHash = (Get-CardFileDigest $target).sha256
        }
        if ($beforeHash -cne $card.sha256) {
            $updates.Add([pscustomobject]@{
                relative = $relative; destination = $target; source = $source
                beforeHash = $beforeHash; sha256 = $card.sha256; bytes = $card.bytes
            })
        }
        $mergedOwned[$card.material] = [pscustomobject][ordered]@{
            material = $card.material; bytes = $card.bytes; sha256 = $card.sha256
        }
    }
    [string[]]$paths = @($mergedOwned.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $installed = [pscustomobject][ordered]@{
        schemaVersion = 1; cards = @($preview.cards); aliases = $preview.aliases
        ownedFiles = @($paths | ForEach-Object { $mergedOwned[$_] })
    }
    Assert-CallingCardCatalogue $installed
    $catalogueText = $installed | ConvertTo-Json -Depth 12
    $catalogueBytes = [Text.UTF8Encoding]::new($false).GetBytes($catalogueText)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $catalogueHash = ([BitConverter]::ToString($algorithm.ComputeHash($catalogueBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
    if ($catalogueHash -cne $previousCatalogueHash) {
        $updates.Add([pscustomobject]@{
            relative = 'data_static/calling_cards.json'; destination = $destinationCatalogue; source = $null
            beforeHash = $previousCatalogueHash; sha256 = $catalogueHash; bytes = $catalogueBytes.Length
        })
    }
    foreach ($update in $updates) {
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $update.destination) -PathType Container)) {
            throw "Calling-card destination directory is missing: $($update.destination)"
        }
    }
    $result = [pscustomobject]@{
        applied = $false; changes = @($updates.ToArray() | ForEach-Object { $_.relative })
        active = $active.Count; retained = $mergedOwned.Count - $active.Count; catalogue = $destinationCatalogue
    }
    if (-not $Apply -or $updates.Count -eq 0) {
        $result.applied = [bool]$Apply
        return $result
    }

    $transaction = Join-Path (Split-Path -Parent $destinationCatalogue) ('.callingcards-stage-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $transaction
    $written = [Collections.Generic.List[object]]::new()
    $removeTransaction = $false
    try {
        $index = 0
        foreach ($update in $updates) {
            $index++
            $prepared = Join-Path $transaction ("new-$index")
            $backup = Join-Path $transaction ("previous-$index")
            if ($null -eq $update.source) { [IO.File]::WriteAllBytes($prepared, $catalogueBytes) }
            else { [IO.File]::Copy($update.source, $prepared) }
            Assert-CardFileDigest $prepared $update
            $update | Add-Member -NotePropertyName prepared -NotePropertyValue $prepared
            $update | Add-Member -NotePropertyName backup -NotePropertyValue $backup
        }
        [IO.File]::WriteAllText((Join-Path $transaction 'journal.json'), (ConvertTo-Json -InputObject @($updates.ToArray()) -Depth 5),
            [Text.UTF8Encoding]::new($false))
        foreach ($update in $updates) {
            $null = Get-CardSafePath $ContentRoot $update.relative
            $existingHash = if (Test-Path -LiteralPath $update.destination) { (Get-CardFileDigest $update.destination).sha256 } else { $null }
            if ($existingHash -cne $update.beforeHash) { throw "Calling-card destination changed during staging: $($update.destination)" }
            if ($null -eq $existingHash) { [IO.File]::Move($update.prepared, $update.destination) }
            else { [IO.File]::Replace($update.prepared, $update.destination, $update.backup) }
            $written.Add($update)
            Assert-CardFileDigest $update.destination $update
            if ($null -ne $AfterWrite) { & $AfterWrite $update.relative | Out-Null }
        }
        $result.applied = $true
        $removeTransaction = $true
        return $result
    } catch {
        $failure = $_.Exception.Message
        $restoreErrors = [Collections.Generic.List[string]]::new()
        for ($index = $written.Count - 1; $index -ge 0; $index--) {
            $update = $written[$index]
            try {
                $current = Get-CardFileDigest $update.destination
                if ($current.sha256 -cne $update.sha256) { throw 'destination changed after our write' }
                if ($null -eq $update.beforeHash) { [IO.File]::Delete($update.destination) }
                else {
                    if (-not (Test-Path -LiteralPath $update.backup -PathType Leaf)) { throw 'original backup is missing' }
                    [IO.File]::Replace($update.backup, $update.destination, ($update.backup + '-discarded'))
                    if ((Get-CardFileDigest $update.destination).sha256 -cne $update.beforeHash) { throw 'restored hash does not match' }
                }
            } catch { $restoreErrors.Add("$($update.destination): $($_.Exception.Message)") }
        }
        if ($restoreErrors.Count -gt 0) {
            throw "Calling-card staging failed: $failure. Restoration incomplete: $($restoreErrors -join '; '). Backups retained at $transaction."
        }
        $removeTransaction = $true
        throw "Calling-card staging failed; previous files and catalogue restored: $failure"
    } finally {
        if ($removeTransaction -and (Test-Path -LiteralPath $transaction)) {
            Remove-Item -LiteralPath $transaction -Recurse -Force
        }
    }
}

function Draw-CardImage {
    param([Drawing.Graphics]$Graphics, [Drawing.Image]$Image, [Drawing.RectangleF]$Destination,
        [Drawing.Color]$Color, [double]$Opacity)
    $attributes = [Drawing.Imaging.ImageAttributes]::new()
    try {
        $matrix = [Drawing.Imaging.ColorMatrix]::new()
        $matrix.Matrix00 = [single]($Color.R / 255.0)
        $matrix.Matrix11 = [single]($Color.G / 255.0)
        $matrix.Matrix22 = [single]($Color.B / 255.0)
        $matrix.Matrix33 = [single](($Color.A / 255.0) * $Opacity)
        $attributes.SetColorMatrix($matrix)
        $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $corners = [Drawing.PointF[]]@(
            [Drawing.PointF]::new($Destination.Left, $Destination.Top),
            [Drawing.PointF]::new($Destination.Right, $Destination.Top),
            [Drawing.PointF]::new($Destination.Left, $Destination.Bottom))
        $Graphics.DrawImage($Image, $corners, [Drawing.RectangleF]::new(0, 0, $Image.Width, $Image.Height),
            [Drawing.GraphicsUnit]::Pixel, $attributes)
    } finally { $attributes.Dispose() }
}

function New-CardImage {
    param([object]$Card, [string]$Destination)
    $canvas = [Drawing.Bitmap]::new($script:CardWidth, $script:CardHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear((ConvertTo-CardColor $Card.baseColor "Base color for $($Card.id)"))
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        foreach ($layer in $Card.layers) {
            if ((Get-FileHash -LiteralPath $layer.image -Algorithm SHA256).Hash.ToLowerInvariant() -cne $layer.sourceHash) {
                throw "Recipe ingredient changed during the build: $($layer.imageKey)"
            }
            $source = [Drawing.Image]::FromFile($layer.image)
            try {
                $colorValue = if ($layer.color.StartsWith('#')) { $layer.color } else { $Card.colors.($layer.color) }
                $color = ConvertTo-CardColor $colorValue "Layer color for $($Card.id)"
                if ($layer.mode -eq 'cover') {
                    $scale = [math]::Max($script:CardWidth / $source.Width, $script:CardHeight / $source.Height) * $layer.scale
                    $width = $source.Width * $scale
                    $height = $source.Height * $scale
                    $rect = [Drawing.RectangleF]::new(
                        [single](($script:CardWidth - $width) / 2 + $layer.offsetX),
                        [single](($script:CardHeight - $height) / 2 + $layer.offsetY),
                        [single]$width, [single]$height)
                    Draw-CardImage $graphics $source $rect $color $layer.opacity
                } else {
                    $width = [math]::Max(1, [math]::Ceiling($source.Width * $layer.scale))
                    $height = [math]::Max(1, [math]::Ceiling($source.Height * $layer.scale))
                    $tile = [Drawing.Bitmap]::new([int]($width + $layer.spacingX), [int]($height + $layer.spacingY),
                        [Drawing.Imaging.PixelFormat]::Format32bppArgb)
                    $tileGraphics = [Drawing.Graphics]::FromImage($tile)
                    try {
                        $tileGraphics.Clear([Drawing.Color]::Transparent)
                        $tileGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        Draw-CardImage $tileGraphics $source ([Drawing.RectangleF]::new(0, 0, [single]$width, [single]$height)) $color $layer.opacity
                    } finally { $tileGraphics.Dispose() }
                    try {
                        $brush = [Drawing.TextureBrush]::new($tile, [Drawing.Drawing2D.WrapMode]::Tile)
                        try {
                            $brush.TranslateTransform([single]$layer.offsetX, [single]$layer.offsetY)
                            $graphics.FillRectangle($brush, 0, 0, $script:CardWidth, $script:CardHeight)
                        } finally { $brush.Dispose() }
                    } finally { $tile.Dispose() }
                }
            } finally { $source.Dispose() }
            if ((Get-FileHash -LiteralPath $layer.image -Algorithm SHA256).Hash.ToLowerInvariant() -cne $layer.sourceHash) {
                throw "Recipe ingredient changed during the build: $($layer.imageKey)"
            }
        }
        $canvas.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $canvas.Dispose() }
}

function Build-CallingCardPreview {
    param([object]$Plan, [string]$OutputDirectory)
    $root = [IO.Path]::GetFullPath($OutputDirectory)
    Assert-CardAncestors $root
    $null = New-Item -ItemType Directory -Force -Path $root
    $directory = Join-Path $root ('build-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory
    $complete = $false
    try {
        $cards = [Collections.Generic.List[object]]::new()
        $owned = [Collections.Generic.List[object]]::new()
        foreach ($card in $Plan.builtins) { $cards.Add($card) }
        foreach ($card in @($Plan.finished) + @($Plan.generated)) {
            $destination = Join-Path $directory ('materials\' + $card.material.Replace('/', '\'))
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
            if ($card.source -eq 'finished') {
                if ((Get-FileHash -LiteralPath $card.sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $card.sourceHash) {
                    throw "Finished image changed during the build: $($card.sourcePath)"
                }
                [IO.File]::Copy($card.sourcePath, $destination)
            } else { New-CardImage $card $destination }
            $info = Get-CardImageInfo $destination -Finished
            if ($card.source -eq 'finished' -and $info.sha256 -cne $card.sourceHash) {
                throw "Finished image copy does not match the artist's original: $($card.sourcePath)"
            }
            $entry = [pscustomobject][ordered]@{
                id = $card.id; name = $card.name; category = $card.category; source = $card.source
                material = $card.material; bytes = $info.bytes; sha256 = $info.sha256
            }
            if ($null -ne $card.PSObject.Properties['shopCredits']) {
                $entry | Add-Member -NotePropertyName shopCredits -NotePropertyValue $card.shopCredits
            }
            $entry | Add-Member -NotePropertyName questReward -NotePropertyValue $card.questReward
            $cards.Add($entry)
            $owned.Add([pscustomobject][ordered]@{ material = $card.material; bytes = $info.bytes; sha256 = $info.sha256 })
        }
        $orderedAliases = [ordered]@{}
        [string[]]$aliasNames = @($Plan.aliases.PSObject.Properties | ForEach-Object { $_.Name })
        [Array]::Sort($aliasNames, [StringComparer]::Ordinal)
        foreach ($name in $aliasNames) { $orderedAliases[$name] = $Plan.aliases.$name }
        $cardsById = @{}
        foreach ($card in $cards) { $cardsById[$card.id] = $card }
        [string[]]$cardIds = @($cardsById.Keys)
        [Array]::Sort($cardIds, [StringComparer]::Ordinal)
        $ownedByPath = @{}
        foreach ($entry in $owned) { $ownedByPath[$entry.material] = $entry }
        [string[]]$ownedPaths = @($ownedByPath.Keys)
        [Array]::Sort($ownedPaths, [StringComparer]::Ordinal)
        $catalogue = [pscustomobject][ordered]@{
            schemaVersion = 1
            cards = @($cardIds | ForEach-Object { $cardsById[$_] })
            aliases = $orderedAliases
            ownedFiles = @($ownedPaths | ForEach-Object { $ownedByPath[$_] })
        }
        $path = Join-Path $directory 'calling_cards.json'
        [IO.File]::WriteAllText($path, ($catalogue | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        Assert-CallingCardCatalogue (Read-CardJson $path)
        $complete = $true
        return [pscustomobject]@{ directory = $directory; catalogue = $path; cards = $catalogue.cards.Count }
    } finally {
        if (-not $complete -and (Test-Path -LiteralPath $directory)) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
}

Export-ModuleMember -Function Get-CallingCardPlan, Build-CallingCardPreview,
    Get-CardIdCategory, Assert-CardMaterial, Assert-CardAliases, Assert-CallingCardCatalogue,
    Get-CardSafePath, Read-CardJson, Install-CallingCardBuild
