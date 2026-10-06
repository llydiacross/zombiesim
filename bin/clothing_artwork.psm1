Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-FittedArtwork {
    param([Parameter(Mandatory)][Drawing.Image]$Image,
        [ValidateRange(1, 1024)][int]$Width, [ValidateRange(1, 1024)][int]$Height,
        [ValidateSet('center', 'bottom')][string]$Alignment = 'center')
    $canvas = [Drawing.Bitmap]::new($Width, $Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $drawing = [Drawing.Graphics]::FromImage($canvas)
    try {
        $drawing.Clear([Drawing.Color]::Transparent)
        $drawing.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $scale = [math]::Min([double]($canvas.Width / $Image.Width), [double]($canvas.Height / $Image.Height))
        $fittedWidth = [single]($Image.Width * $scale)
        $fittedHeight = [single]($Image.Height * $scale)
        $y = if ($Alignment -eq 'bottom') { $canvas.Height - $fittedHeight } else { ($canvas.Height - $fittedHeight) / 2 }
        $destination = [Drawing.RectangleF]::new(($canvas.Width - $fittedWidth) / 2, $y, $fittedWidth, $fittedHeight)
        if ($Alignment -eq 'bottom') {
            $attributes = [Drawing.Imaging.ImageAttributes]::new()
            try {
                $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $corners = [Drawing.PointF[]]@(
                    [Drawing.PointF]::new($destination.Left, $destination.Top),
                    [Drawing.PointF]::new($destination.Right, $destination.Top),
                    [Drawing.PointF]::new($destination.Left, $destination.Bottom))
                $drawing.DrawImage($Image, $corners, [Drawing.RectangleF]::new(0, 0, $Image.Width, $Image.Height),
                    [Drawing.GraphicsUnit]::Pixel, $attributes)
            } finally { $attributes.Dispose() }
        } else {
            $drawing.DrawImage($Image, $destination)
        }
    } catch { $canvas.Dispose(); throw }
    finally { $drawing.Dispose() }
    return $canvas
}

function Get-ClothingLegPresets {
    param([Parameter(Mandatory)]$Prints)
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\clothing\pants_cuffs.json'
    $cuffs = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($cuffs.schemaVersion -ne 1 -or $cuffs.presets.Count -ne 3 -or
        ($cuffs.presets.id -join ',') -ne 'pants_cuff,pants_cuff_right,pants_cuff_both') { throw 'Invalid cuff placement presets.' }
    foreach ($preset in $cuffs.presets) {
        if ($preset.alignment -ne 'bottom') { throw "Cuff artwork must retain bottom alignment: $($preset.id)" }
    }
    return @($Prints.pantsLeg, $Prints.pantsLegRight) + @($cuffs.presets) +
        @(Get-ClothingRearPresets | Where-Object { $_.id -like 'pants_*' })
}

function Get-ClothingRearPresets {
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\clothing\rear_limbs.json'
    $rear = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($rear.schemaVersion -ne 1 -or
        ($rear.presets.id -join ',') -ne 'pants_back_left,pants_back_right,arm_back_left,arm_back_right') {
        throw 'Invalid rear-limb placement presets.'
    }
    return @($rear.presets)
}

function Get-ClothingSleevePresets {
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\clothing\sleeve_cuffs.json'
    $cuffs = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($cuffs.schemaVersion -ne 1 -or $cuffs.presets.Count -ne 3 -or
        ($cuffs.presets.id -join ',') -ne 'sleeve_cuff,sleeve_cuff_right,sleeve_cuff_both') { throw 'Invalid sleeve cuff placement presets.' }
    foreach ($preset in $cuffs.presets) {
        if ($preset.alignment -ne 'bottom') { throw "Sleeve cuff artwork must retain bottom alignment: $($preset.id)" }
    }
    return @($cuffs.presets)
}

function Get-ClothingShirtPresets {
    param([Parameter(Mandatory)]$Prints)
    return @($Prints.styles) + @(Get-ClothingSleevePresets) + @(Get-ClothingRearPresets | Where-Object { $_.id -like 'arm_*' })
}

Export-ModuleMember -Function New-FittedArtwork, Get-ClothingLegPresets, Get-ClothingRearPresets, Get-ClothingSleevePresets, Get-ClothingShirtPresets
