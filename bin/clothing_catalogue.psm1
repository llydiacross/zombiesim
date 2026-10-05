Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'clothing_artwork.psm1')

function Get-ClothingToneContrast {
    param([Parameter(Mandatory)][ValidateSet('light', 'dark')][string]$Tone,
        [Parameter(Mandatory)][ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$Background)
    $luminance = 0.0
    $weights = @(0.2126, 0.7152, 0.0722)
    for ($index = 0; $index -lt 3; $index++) {
        $channel = [Convert]::ToInt32($Background.Substring(1 + 2 * $index, 2), 16) / 255.0
        $linear = if ($channel -le 0.04045) { $channel / 12.92 } else { [math]::Pow(($channel + 0.055) / 1.055, 2.4) }
        $luminance += $weights[$index] * $linear
    }
    if ($Tone -eq 'dark') { return ($luminance + 0.05) / 0.05 }
    return 1.05 / ($luminance + 0.05)
}

function Read-ClothingFilename {
    param([Parameter(Mandatory)][string]$Filename, [Parameter(Mandatory)]$Settings)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Filename).ToLowerInvariant()
    if ($stem -notmatch '^[a-z0-9][a-z0-9 _-]*$') { throw "Artwork requires an ASCII letter/digit filename: $Filename" }
    $identity = ($stem -replace '[ _-]+', '_').TrimEnd('_')
    if ($identity.Length -gt 36) { throw "Artwork identity exceeds 36 characters: $Filename" }
    $tokens = [Collections.Generic.List[string]]::new()
    foreach ($token in $identity.Split('_')) { $tokens.Add($token) }
    $colour = $null
    $placement = $null
    $artworkTone = $null
    $excludedColours = [Collections.Generic.List[string]]::new()
    while ($tokens.Count -gt 0) {
        $last = $tokens[$tokens.Count - 1]
        if ($last -in 'light', 'dark') {
            if ($null -ne $artworkTone) { throw "Ambiguous artwork tone suffixes: $Filename" }
            $artworkTone = $last
            $tokens.RemoveAt($tokens.Count - 1)
            continue
        }
        if ($last.StartsWith('not') -and $last.Length -gt 3) {
            $excluded = $last.Substring(3)
            if ($excluded -eq 'gray') { $excluded = 'grey' }
            if ($null -ne $Settings.colours.PSObject.Properties[$excluded]) {
                if ($excludedColours.Contains($excluded)) { throw "Repeated colour exclusion: $Filename" }
                $excludedColours.Add($excluded)
                $tokens.RemoveAt($tokens.Count - 1)
                continue
            }
        }
        $canonicalColour = if ($last -eq 'gray') { 'grey' } else { $last }
        if ($null -ne $Settings.colours.PSObject.Properties[$canonicalColour]) {
            if ($null -ne $colour) { throw "Ambiguous colour suffixes: $Filename" }
            $colour = $canonicalColour
            $tokens.RemoveAt($tokens.Count - 1)
            continue
        }
        $tag = $last
        $length = 1
        if ($tokens.Count -ge 3 -and $tokens[$tokens.Count - 3] -in 'pants', 'arm' -and
            $tokens[$tokens.Count - 2] -eq 'back' -and $last -in 'left', 'right') {
            $tag = $tokens[$tokens.Count - 3] + '_back_' + $last
            $length = 3
        }
        if ($tokens.Count -ge 2 -and $tokens[$tokens.Count - 2] -eq 'pants' -and $last -eq 'cuff') {
            $tag = 'pants_cuff'
            $length = 2
        }
        if ($tokens.Count -ge 2 -and $tokens[$tokens.Count - 2] -eq 'arm' -and $last -in 'left', 'right') {
            $tag = 'arm_' + $last
            $length = 2
        }
        if ($tokens.Count -ge 2 -and $tokens[$tokens.Count - 2] -in 'front', 'back' -and $last -eq 'full') {
            $tag = $tokens[$tokens.Count - 2]
            $length = 2
        }
        if ($tag -in 'chest', 'front', 'back', 'arm_left', 'arm_right', 'pants', 'pants_cuff',
            'pants_back_left', 'pants_back_right', 'arm_back_left', 'arm_back_right') {
            if ($null -ne $placement) { throw "Ambiguous placement suffixes: $Filename" }
            $placement = $tag
            $tokens.RemoveRange($tokens.Count - $length, $length)
            continue
        }
        break
    }
    if ($tokens.Count -eq 0) { throw "Artwork requires a family name before suffixes: $Filename" }
    if ($null -ne $colour -and $excludedColours.Contains($colour)) { throw "Fixed colour is also excluded: $Filename" }
    return [pscustomobject]@{ source = $Filename; identity = $identity; family = $tokens -join '_';
        colour = $colour; placement = $placement; excludedColours = $excludedColours.ToArray(); artworkTone = $artworkTone }
}

function Get-ClothingCataloguePlan {
    param([Parameter(Mandatory)][string]$ArtworkRoot, [Parameter(Mandatory)]$Settings)
    if ($Settings.schemaVersion -ne 1 -or $Settings.maximumImages -lt 1 -or $Settings.maximumImages -gt 64 -or
        $Settings.maximumVariants -lt 1 -or $Settings.maximumVariants -gt 1024) { throw 'Invalid clothing catalogue schema/budgets.' }
    if ($Settings.minimumToneContrast -lt 3 -or $Settings.minimumToneContrast -gt 21) { throw 'Artwork tone contrast must be 3-21.' }
    foreach ($property in $Settings.colours.PSObject.Properties) {
        if ($property.Name -notmatch '^[a-z]+$' -or $property.Value -notmatch '^#[0-9A-Fa-f]{6}$') { throw 'Invalid catalogue colour.' }
    }
    foreach ($name in @($Settings.shirtColours) + @($Settings.pantsColours)) {
        if ($null -eq $Settings.colours.PSObject.Properties[$name]) { throw "Unknown curated clothing colour: $name" }
    }
    foreach ($values in $Settings.shirtColours, $Settings.pantsColours, $Settings.defaultShirtPlacements) {
        if (@($values).Count -lt 1 -or @($values).Count -gt 7 -or
            @($values | Select-Object -Unique).Count -ne @($values).Count) { throw 'Curated palettes/placements must be nonempty, distinct and bounded.' }
    }
    foreach ($tone in 'light', 'dark') {
        foreach ($garment in 'shirt', 'pants') {
            $palette = @($Settings.tonePalettes.$tone.$garment)
            if ($palette.Count -lt 1 -or $palette.Count -gt 7 -or
                @($palette | Select-Object -Unique).Count -ne $palette.Count) { throw "Invalid $tone/$garment tone palette." }
            foreach ($colour in $palette) {
                if ($null -eq $Settings.colours.PSObject.Properties[$colour]) { throw "Unknown tone-palette colour: $colour" }
                if ((Get-ClothingToneContrast $tone $Settings.colours.$colour) -lt $Settings.minimumToneContrast) {
                    throw "Tone palette colour $colour has insufficient contrast for $tone artwork."
                }
            }
        }
    }
    foreach ($placement in $Settings.defaultShirtPlacements) {
        if ($placement -notin 'chest', 'chest_left', 'chest_right', 'front_full', 'back_full', 'back_small', 'arm_left', 'arm_right') {
            throw "Invalid default shirt placement: $placement"
        }
    }
    Add-Type -AssemblyName System.Drawing
    $images = @(Get-ChildItem -LiteralPath $ArtworkRoot -File |
        Where-Object { $_.Extension -ieq '.png' -and $_.Name -notin $Settings.excludeFiles -and -not $_.Name.StartsWith('__') } |
        Sort-Object Name)
    if ($images.Count -gt $Settings.maximumImages) { throw 'Clothing image budget exceeded; narrow the eligible folder/configuration.' }
    $families = [Collections.Generic.List[object]]::new()
    $variants = [Collections.Generic.List[object]]::new()
    $seen = @{}
    $ids = @{}
    foreach ($image in $images) {
        if (($image.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Artwork symlinks are not eligible: $($image.Name)" }
        $family = Read-ClothingFilename $image.Name $Settings
        if ($seen.ContainsKey($family.identity)) { throw "Normalized artwork identity collision: $($image.Name)" }
        $seen[$family.identity] = $true
        $bitmap = [Drawing.Bitmap]::new($image.FullName)
        try {
            if ($bitmap.Width -lt 1 -or $bitmap.Height -lt 1 -or $bitmap.Width -gt 4096 -or $bitmap.Height -gt 4096) {
                throw "Artwork dimensions must be 1-4096 per axis: $($image.Name)"
            }
            $family | Add-Member -NotePropertyName width -NotePropertyValue $bitmap.Width
            $family | Add-Member -NotePropertyName height -NotePropertyValue $bitmap.Height
        } finally { $bitmap.Dispose() }
        $family | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $image.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $families.Add($family)
        $garments = if ($family.placement -eq 'pants' -or $family.placement -like 'pants_*') { @('pants') }
            elseif ($null -ne $family.placement) { @('shirt') } else { @('shirt', 'pants') }
        foreach ($garment in $garments) {
            $colours = if ($null -ne $family.colour) { @($family.colour) }
                elseif ($null -ne $family.artworkTone) { @($Settings.tonePalettes.($family.artworkTone).$garment) }
                elseif ($garment -eq 'shirt') { @($Settings.shirtColours) } else { @($Settings.pantsColours) }
            $colours = @($colours | Where-Object { $_ -notin $family.excludedColours })
            if ($null -ne $family.artworkTone) {
                $colours = @($colours | Where-Object {
                    (Get-ClothingToneContrast $family.artworkTone $Settings.colours.$_) -ge $Settings.minimumToneContrast
                })
            }
            if ($colours.Count -eq 0) { throw "No allowed $garment colours remain for $($family.source) after exclusions/tone contrast; change suffixes or curated palette." }
            $placements = if ($garment -eq 'pants') {
                    if ($family.placement -like 'pants_back_*') { @($family.placement) }
                    elseif ($family.placement -eq 'pants_cuff') { @('pants_cuff', 'pants_cuff_right') }
                    else { @('pants_leg', 'pants_leg_right', 'pants_cuff', 'pants_cuff_right') }
                }
                elseif ($family.placement -eq 'front') { @('front_full') }
                elseif ($family.placement -eq 'back') { @('back_full') }
                elseif ($null -ne $family.placement) { @($family.placement) } else { @($Settings.defaultShirtPlacements) }
            foreach ($colour in $colours) {
                foreach ($style in @($placements) + @('repeat')) {
                    $finish = 'catalogue_' + $family.identity + '_' + $garment + '_' + $colour + '_' + $style
                    $item = 'itemClothing' + (($finish.Substring(10).Split('_') | ForEach-Object {
                        $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
                    }) -join '')
                    if ($ids.ContainsKey($item)) { throw "Generated clothing item collision: $item" }
                    $ids[$item] = $true
                    $variants.Add([pscustomobject]@{ id = $finish; itemId = $item; family = $family.identity;
                        source = $family.source; garment = $garment; colour = $colour;
                        background = $Settings.colours.$colour; style = $style; clean = $true;
                        artworkTone = $family.artworkTone })
                    if ($variants.Count -gt $Settings.maximumVariants) { throw 'Clothing variant budget exceeded; reduce palettes/placements.' }
                }
            }
        }
    }
    return [pscustomobject]@{ schemaVersion = 1; releaseEligible = $false;
        provenance = 'Original generated finishes; supplied image redistribution rights remain unverified.';
        families = $families.ToArray(); variants = $variants.ToArray() }
}

function Get-ClothingCatalogueIcon {
    param([Parameter(Mandatory)][ValidateSet('shirt', 'pants')][string]$Garment,
        [Parameter(Mandatory)][string]$Style, [Parameter(Mandatory)]$Prints)
    if ($Style -eq 'repeat') {
        $uv = if ($Garment -eq 'shirt') { @(144, 764, 176, 224) } else { @(784, 72, 88, 312) }
        return [ordered]@{ size = @($uv[2], $uv[3]); male = @(@{ uv = $uv; source = @(0, 0, $uv[2], $uv[3]) });
            female = @(@{ uv = $(if ($Garment -eq 'shirt') { @(163, 764, 176, 224) } else { @(812, 52, 88, 312) });
                source = @(0, 0, $uv[2], $uv[3]) }) }
    }
    $preset = if ($Style -like 'pants_*') { @(Get-ClothingLegPresets $Prints | Where-Object id -eq $Style) }
        else { @(Get-ClothingShirtPresets $Prints | Where-Object id -eq $Style) }
    if (@($preset).Count -ne 1) { throw "Missing or ambiguous wardrobe icon placement: $Style" }
    return [ordered]@{ size = $preset.size; male = @($preset.male); female = @($preset.female) }
}

Export-ModuleMember -Function Read-ClothingFilename, Get-ClothingCataloguePlan, Get-ClothingToneContrast, Get-ClothingCatalogueIcon
