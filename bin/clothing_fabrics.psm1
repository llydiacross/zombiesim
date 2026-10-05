Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if ($null -eq ('ZombieSimFabricRendererV3' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'clothing_fabric_renderer.cs') -ReferencedAssemblies System.Drawing
}

function Test-ClothingFabric {
    param([Parameter(Mandatory)]$Design)
    if ($Design.pattern -notin 'solid', 'stripes', 'checker', 'tie_dye' -or
        $Design.color -notmatch '^#[0-9A-Fa-f]{6}$' -or $Design.stripeColor -notmatch '^#[0-9A-Fa-f]{6}$') {
        throw 'Invalid clothing fabric pattern/colours.'
    }
    foreach ($value in $Design.stripeSpacing, $Design.stripeWidth) {
        if ($value -ne [math]::Floor($value) -or $value -lt 1 -or $value -gt 1024) { throw 'Invalid fabric stripe/check dimensions.' }
    }
    if ($Design.stripeWidth -gt $Design.stripeSpacing) { throw 'Fabric stripe width exceeds spacing.' }
    if ($Design.pattern -eq 'tie_dye') {
        $dye = $Design.tieDye
        if ($dye.palette.Count -lt 2 -or $dye.palette.Count -gt 5 -or
            $dye.scale -lt 32 -or $dye.scale -gt 512 -or $dye.strength -lt 0 -or $dye.strength -gt 1 -or
            $dye.seed -ne [math]::Floor($dye.seed) -or $dye.seed -lt 0 -or $dye.seed -gt 65535) {
            throw 'Invalid tie-dye palette/scale/strength/seed.'
        }
        foreach ($colour in $dye.palette) {
            if ($colour -notmatch '^#[0-9A-Fa-f]{6}$') { throw 'Invalid tie-dye palette colour.' }
        }
        if ($dye.center.Count -ne 2) { throw 'Tie-dye center requires two UV coordinates.' }
        foreach ($value in $dye.center) {
            if ($value -ne [math]::Floor($value) -or $value -lt 0 -or $value -gt 1024) { throw 'Invalid tie-dye center.' }
        }
        if ($null -ne $dye.PSObject.Properties['style'] -and $dye.style -notin 'spiral', 'rings', 'cloud', 'marble') {
            throw 'Invalid tie-dye style.'
        }
    }
}

function Write-ClothingFabric {
    param([Parameter(Mandatory)][Drawing.Graphics]$Graphics, [Parameter(Mandatory)]$Design)
    Test-ClothingFabric $Design
    $base = [Drawing.ColorTranslator]::FromHtml($Design.color)
    $brush = [Drawing.SolidBrush]::new($base)
    $accent = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($Design.stripeColor))
    try {
        $Graphics.FillRectangle($brush, 0, 0, 1024, 1024)
        if ($Design.pattern -eq 'stripes') {
            for ($y = 0; $y -lt 1024; $y += $Design.stripeSpacing) { $Graphics.FillRectangle($accent, 0, $y, 1024, $Design.stripeWidth) }
        } elseif ($Design.pattern -eq 'checker') {
            for ($y = 0; $y -lt 1024; $y += $Design.stripeSpacing) {
                for ($x = 0; $x -lt 1024; $x += $Design.stripeSpacing) {
                    if ((($x + $y) / $Design.stripeSpacing) % 2 -eq 1) {
                        $Graphics.FillRectangle($accent, $x, $y, $Design.stripeSpacing, $Design.stripeSpacing)
                    }
                }
            }
        } elseif ($Design.pattern -eq 'tie_dye') {
            $dye = $Design.tieDye
            $palette = [Drawing.Color[]]@($dye.palette | ForEach-Object { [Drawing.ColorTranslator]::FromHtml($_) })
            $style = if ($null -ne $dye.PSObject.Properties['style']) { $dye.style } else { 'spiral' }
            [ZombieSimFabricRendererV3]::DrawDye($Graphics, $base, $palette, $dye.center[0], $dye.center[1],
                $dye.scale, $dye.strength, $dye.seed, $style)
        }
    } finally { $brush.Dispose(); $accent.Dispose() }
}

function Get-ClothingFabricPlan {
    param([Parameter(Mandatory)]$Settings, [Parameter(Mandatory)]$Catalogue)
    if ($Settings.schemaVersion -ne 1 -or $Settings.maximumVariants -lt 1 -or $Settings.maximumVariants -gt 256 -or
        $Settings.variants.Count -gt $Settings.maximumVariants) { throw 'Invalid fabric catalogue schema/budget.' }
    $variants = @($Settings.variants)
    if ($null -ne $Settings.PSObject.Properties['expansion']) {
        $expansion = $Settings.expansion
        if ($expansion.colours.Count -lt 1 -or $expansion.colours.Count -gt 15 -or
            @($expansion.colours | Select-Object -Unique).Count -ne $expansion.colours.Count) {
            throw 'Invalid fabric expansion colours.'
        }
        foreach ($colour in $expansion.colours) {
            if ($null -eq $Catalogue.colours.PSObject.Properties[$colour]) { throw "Unknown fabric expansion colour: $colour" }
            $base = [Drawing.ColorTranslator]::FromHtml($Catalogue.colours.$colour)
            $dark = [Drawing.Color]::FromArgb([int]($base.R * 0.55), [int]($base.G * 0.55), [int]($base.B * 0.55))
            $light = [Drawing.Color]::FromArgb([int]($base.R * 0.45 + 140), [int]($base.G * 0.45 + 140), [int]($base.B * 0.45 + 140))
            $subdued = [Drawing.Color]::FromArgb([math]::Min(255, $base.R + 4), [math]::Min(255, $base.G + 4), [math]::Min(255, $base.B + 4))
            $hex = { param($c) '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B }
            foreach ($garment in 'shirt', 'pants') {
                $treatments = if ($garment -eq 'shirt') { @($expansion.shirtTreatments) } else { @($expansion.pantsTreatments) }
                if ($treatments.Count -lt 1 -or $treatments.Count -gt 12 -or
                    @($treatments.id | Select-Object -Unique).Count -ne $treatments.Count) { throw 'Invalid fabric expansion treatments.' }
                foreach ($treatment in $treatments) {
                    if ($treatment.id -notmatch '^[a-z][a-z0-9]{1,12}$') { throw 'Invalid fabric treatment identity.' }
                    $accent = if ($garment -eq 'pants') { & $hex $subdued } else { & $hex $dark }
                    $fabric = [pscustomobject]@{ id = "${garment}_${colour}_$($treatment.id)"; garment = $garment;
                        colour = $colour; pattern = $treatment.pattern; color = $Catalogue.colours.$colour;
                        stripeColor = $accent; stripeSpacing = $treatment.spacing; stripeWidth = $treatment.width }
                    if ($treatment.pattern -eq 'tie_dye') {
                        $fabric | Add-Member -NotePropertyName tieDye -NotePropertyValue ([pscustomobject]@{
                            palette = @($Catalogue.colours.$colour, (& $hex $dark), (& $hex $light));
                            center = @(232, 876); scale = $treatment.spacing; strength = 0.9;
                            seed = $treatment.seed; style = $treatment.style })
                    }
                    $variants += $fabric
                    if ($variants.Count -gt $Settings.maximumVariants) { throw 'Expanded fabric catalogue exceeds variant budget.' }
                }
            }
        }
    }
    $seen = @{}
    $itemIds = @{}
    foreach ($fabric in $variants) {
        Test-ClothingFabric $fabric
        if ($fabric.id -notmatch '^[a-z][a-z0-9_]{1,35}$' -or $seen.ContainsKey($fabric.id) -or
            $fabric.garment -notin 'shirt', 'pants' -or $null -eq $Catalogue.colours.PSObject.Properties[$fabric.colour]) {
            throw 'Invalid/duplicate fabric identity, garment or colour.'
        }
        if ($fabric.garment -eq 'pants' -and $fabric.pattern -eq 'tie_dye' -and $fabric.tieDye.strength -gt 0.2) {
            throw 'Pants dye strength must remain subdued (at most 0.2).'
        }
        $seen[$fabric.id] = $true
        $itemId = 'itemClothingFabric' + (($fabric.id.Split('_') | ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
            }) -join '')
        if ($itemIds.ContainsKey($itemId)) { throw "Fabric item identity collision: $itemId" }
        $itemIds[$itemId] = $true
        [pscustomobject]@{ id = 'catalogue_fabric_' + $fabric.id; garment = $fabric.garment;
            itemId = $itemId; colour = $fabric.colour; style = $fabric.pattern; design = $fabric }
    }
}

Export-ModuleMember -Function Test-ClothingFabric, Write-ClothingFabric, Get-ClothingFabricPlan
