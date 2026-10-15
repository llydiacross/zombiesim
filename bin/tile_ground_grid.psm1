Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')
$script:GroundGridWarnings = @{}
$script:GroundTopMaterials = @('DE_CBBLE/GRASSFLOOR01', 'CS_HAVANA/GROUND01GRASS', 'CS_HAVANA/SWAMPDIRT01', 'NATURE/SANDFLOOR005A', 'GM_CONSTRUCT/FLATGRASS_2', 'DEV/VALUESAND40', 'CONCRETE/CONCRETEFLOOR038A', 'CONCRETE/CONCRETEFLOOR009A')

function Get-ZMTileGroundBases {
    param([Parameter(Mandatory)][string]$Path, [string]$Text = '', [switch]$Partitioned)

    if ($Text.Length -eq 0) { $Text = [IO.File]::ReadAllText($Path) }
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse($Text)
    $world = $tree.Child('world')
    if ($null -eq $world) { throw "Tile has no world block: $Path" }
    foreach ($solid in @($world.Children | Where-Object Name -eq solid)) {
        $sides = @($solid.Children | Where-Object Name -eq side)
        if ($sides.Count -ne 6 -or @($sides | Where-Object { $null -ne $_.Child('dispinfo') -or $null -eq $_.Child('vertices_plus') }).Count -gt 0) { continue }
        $points = @($sides | ForEach-Object { $_.Child('vertices_plus').GetAll('v') } | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_) })
        if ($points.Count -ne 24) { continue }
        $bounds = @{}
        foreach ($axis in @('X', 'Y', 'Z')) {
            $bounds[$axis] = $points | Measure-Object $axis -Minimum -Maximum
        }
        if ([Math]::Abs($bounds.Z.Minimum) -gt 0.001 -or $bounds.Z.Maximum -ne 32) { continue }
        $top = @($sides | Where-Object {
            $vertices = @($_.Child('vertices_plus').GetAll('v') | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_) })
            @($vertices | Where-Object Z -ne 32).Count -eq 0
        })
        if ($top.Count -ne 1 -or $top[0].Get('material') -notin $script:GroundTopMaterials) { continue }
        if (@($sides | Where-Object {
            $_ -ne $top[0] -and $_.Get('material') -ne 'BUILDING_TEMPLATE/BUILDING_TEMPLATE028A' -and
            (-not $Partitioned -or $_.Get('material') -notin $script:GroundTopMaterials)
        }).Count -gt 0) { continue }
        $box = $true
        foreach ($point in $points) {
            foreach ($axis in @('X', 'Y', 'Z')) {
                if ([Math]::Min([Math]::Abs($point.$axis - $bounds[$axis].Minimum), [Math]::Abs($point.$axis - $bounds[$axis].Maximum)) -gt 0.001) { $box = $false }
            }
        }
        if (-not $box) { continue }
        $width = $bounds.X.Maximum - $bounds.X.Minimum
        $height = $bounds.Y.Maximum - $bounds.Y.Minimum
        # Partial slabs have explicit independent footprints, not the full-tile contract.
        if (-not $Partitioned -and ([Math]::Abs($width - 640) -gt 32 -or [Math]::Abs($height - 640) -gt 32)) { continue }
        if ($width -le 0 -or $height -le 0) { continue }
        [pscustomobject]@{ solid = $solid; sides = $sides; bounds = $bounds; width = $width; height = $height }
    }
}

function Get-ZMTileGroundReference {
    param([Parameter(Mandatory)][string]$Path, [string]$Text = '')

    $bases = @(Get-ZMTileGroundBases $Path -Text $Text -Partitioned)
    if ($bases.Count -eq 0) { return }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $width = 1
    $height = 1
    if ($name -match '_(\d+)x(\d+)$') { $width = [int]$Matches[1]; $height = [int]$Matches[2] }
    elseif ($name -match '_(\d+)x$') { $width = [int]$Matches[1]; $height = $width }
    elseif ((Split-Path -Leaf (Split-Path -Parent $Path)) -eq 'motorway_3x1') { $width = 3; $height = 1 }
    $minX = ($bases | ForEach-Object { $_.bounds.X.Minimum } | Measure-Object -Minimum).Minimum
    $maxX = ($bases | ForEach-Object { $_.bounds.X.Maximum } | Measure-Object -Maximum).Maximum
    $minY = ($bases | ForEach-Object { $_.bounds.Y.Minimum } | Measure-Object -Minimum).Minimum
    $maxY = ($bases | ForEach-Object { $_.bounds.Y.Maximum } | Measure-Object -Maximum).Maximum
    $centerX = $minX + ($maxX - $minX) / 2
    $centerY = $minY + ($maxY - $minY) / 2
    $complete = [Math]::Abs($maxX - $minX - $width * 640) -le 0.001 -and [Math]::Abs($maxY - $minY - $height * 640) -le 0.001
    $area = 0.0
    for ($i = 0; $i -lt $bases.Count; $i++) {
        $a = $bases[$i]
        $area += $a.width * $a.height
        for ($j = $i + 1; $j -lt $bases.Count; $j++) {
            $b = $bases[$j]
            if ($a.bounds.X.Minimum -lt $b.bounds.X.Maximum -and $a.bounds.X.Maximum -gt $b.bounds.X.Minimum -and
                $a.bounds.Y.Minimum -lt $b.bounds.Y.Maximum -and $a.bounds.Y.Maximum -gt $b.bounds.Y.Minimum) { $complete = $false }
        }
    }
    $expectedArea = ($maxX - $minX) * ($maxY - $minY)
    $areaRoundoff = 16 * [Math]::Pow(2, -52) * $expectedArea * $bases.Count
    if ([Math]::Abs($area - $expectedArea) -gt $areaRoundoff) { $complete = $false }
    [pscustomobject]@{ source = [IO.Path]::GetFullPath($Path); centerX = $centerX; centerY = $centerY; width = $width; height = $height; complete = $complete; baseCount = $bases.Count }
}

function Get-ZMTileGroundGridIssues {
    param([Parameter(Mandatory)][string]$Path, [string]$Text = '')

    foreach ($base in @(Get-ZMTileGroundBases $Path -Text $Text)) {
        $bounds = $base.bounds
        $coordinates = [System.Collections.Generic.List[string]]::new()
        $repairable = $true
        foreach ($axis in @('X', 'Y', 'Z')) {
            $pitch = if ($axis -eq 'Z') { 32 } else { 320 }
            foreach ($value in @($bounds[$axis].Minimum, $bounds[$axis].Maximum)) {
                $nearest = [Math]::Round($value / $pitch, [MidpointRounding]::AwayFromZero) * $pitch
                if ($nearest -ne $value) { $coordinates.Add("$axis=$($value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)) -> $nearest") }
                if ([Math]::Abs($value - $nearest) -ge 1) { $repairable = $false }
            }
        }
        foreach ($side in $base.sides) {
            $plane = [regex]::Matches($side.Get('plane'), '-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?')
            if ($plane.Count -ne 9) { throw "Invalid brush plane: $Path solid $($base.solid.Get('id'))" }
            for ($i = 0; $i -lt 9; $i++) {
                $value = [double]::Parse($plane[$i].Value, [Globalization.CultureInfo]::InvariantCulture)
                $pitch = if ($i % 3 -eq 2) { 32 } else { 320 }
                $nearest = [Math]::Round($value / $pitch, [MidpointRounding]::AwayFromZero) * $pitch
                if ($nearest -ne $value) { $coordinates.Add("plane side $($side.Get('id')) component $i=$($plane[$i].Value) -> $nearest") }
                if ([Math]::Abs($value - $nearest) -ge 1) { $repairable = $false }
            }
        }
        if ($coordinates.Count -eq 0) { continue }
        [pscustomobject]@{ source = [IO.Path]::GetFullPath($Path); solidId = $base.solid.Get('id'); width = $base.width; height = $base.height; repairable = $repairable; coordinates = $coordinates.ToArray() }
    }
}

function Repair-ZMTileGroundGridText {
    param([string]$Text, [object[]]$Issues)

    $ids = @{}
    foreach ($issue in $Issues) {
        if (-not $issue.repairable) { throw "Ground alignment requires manual review: $($issue.source) solid $($issue.solidId)" }
        $ids[$issue.solidId] = $true
    }
    [regex]::Replace($Text, '(?ms)^([ \t]*)solid\r?\n\1\{.*?^\1\}', {
        param($match)
        $id = [regex]::Match($match.Value, '"id"\s+"(\d+)"').Groups[1].Value
        if (-not $ids.ContainsKey($id)) { return $match.Value }
        [regex]::Replace($match.Value, '("(?:plane|v)"\s+")([^"]+)(")', {
            param($coordinate)
            $value = $coordinate.Groups[2].Value
            $scalars = [regex]::Matches($value, '-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?')
            for ($i = $scalars.Count - 1; $i -ge 0; $i--) {
                $scalar = $scalars[$i]
                $pitch = if ($i % 3 -eq 2) { 32 } else { 320 }
                $original = [double]::Parse($scalar.Value, [Globalization.CultureInfo]::InvariantCulture)
                $snapped = ([Math]::Round($original / $pitch, [MidpointRounding]::AwayFromZero) * $pitch).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
                $value = $value.Remove($scalar.Index, $scalar.Length).Insert($scalar.Index, $snapped)
            }
            $coordinate.Groups[1].Value + $value + $coordinate.Groups[3].Value
        }.GetNewClosure())
    }.GetNewClosure())
}

function Move-ZMTileGroundOriginText {
    param([string]$Text, [object]$Reference)

    if (-not $Reference.complete) { throw "Incomplete/asymmetric ground cannot establish an origin: $($Reference.source)" }
    if ($Text -match '(?i)\bdispinfo\b|"classname"\s+"info_overlay"') { throw "Origin translation requires manual review for displacements or overlays: $($Reference.source)" }
    $offset = @(-$Reference.centerX, -$Reference.centerY, 0.0)
    $number = '-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?'
    $moved = [regex]::Replace($Text, '("(?:plane|v|origin)"\s+")([^"]+)(")', {
        param($coordinate)
        $value = $coordinate.Groups[2].Value
        $scalars = [regex]::Matches($value, $number)
        $expected = if ($coordinate.Groups[1].Value.Contains('"plane"')) { 9 } else { 3 }
        if ($scalars.Count -ne $expected) { throw "Unsupported geometry coordinates during origin translation: $($Reference.source)" }
        for ($i = $scalars.Count - 1; $i -ge 0; $i--) {
            $scalar = $scalars[$i]
            $axis = $i % 3
            if ($offset[$axis] -eq 0) { continue }
            $original = [double]::Parse($scalar.Value, [Globalization.CultureInfo]::InvariantCulture)
            $translated = ([double]($original + $offset[$axis])).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            $value = $value.Remove($scalar.Index, $scalar.Length).Insert($scalar.Index, $translated)
        }
        $coordinate.Groups[1].Value + $value + $coordinate.Groups[3].Value
    }.GetNewClosure())
    # Texture locking retains the same UV at every translated surface point.
    [regex]::Replace($moved, '("(?:uaxis|vaxis)"\s+"\[)([^\]]+)(\]\s+)([^"]+)(")', {
        param($axis)
        $values = @($axis.Groups[2].Value -split '\s+' | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) })
        if ($values.Count -ne 4) { throw "Invalid texture axis: $($Reference.source)" }
        $scale = [double]::Parse($axis.Groups[4].Value, [Globalization.CultureInfo]::InvariantCulture)
        if ($scale -eq 0) { throw "Zero texture scale: $($Reference.source)" }
        $shift = ($values[0] * $offset[0] + $values[1] * $offset[1] + $values[2] * $offset[2]) / $scale
        if ($shift -eq 0) { return $axis.Value }
        $values[3] -= $shift
        $axis.Groups[1].Value + (($values | ForEach-Object { $_.ToString('R', [Globalization.CultureInfo]::InvariantCulture) }) -join ' ') + $axis.Groups[3].Value + $axis.Groups[4].Value + $axis.Groups[5].Value
    }.GetNewClosure())
}

function Write-ZMTileGroundGridWarnings {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath -notmatch '(?i)[\\/]tiletemplates[\\/]' -or $fullPath -match '(?i)[\\/]terrain[\\/]infill[\\/]') { return }
    $file = Get-Item -LiteralPath $fullPath
    $key = "$fullPath|$($file.LastWriteTimeUtc.Ticks)|$($file.Length)"
    if ($script:GroundGridWarnings.ContainsKey($key)) { return }
    foreach ($issue in @(Get-ZMTileGroundGridIssues $fullPath)) {
        Write-Warning ("Tile ground alignment: {0}; solid {1}; {2}; repairable={3}. Run repair_tile_ground_grid.ps1 for explicit source repair." -f $fullPath, $issue.solidId, ($issue.coordinates -join '; '), $issue.repairable)
    }
    $reference = Get-ZMTileGroundReference $fullPath
    if ($null -ne $reference -and $reference.complete -and ([Math]::Abs($reference.centerX) -gt 0.001 -or [Math]::Abs($reference.centerY) -gt 0.001)) {
        Write-Warning "Tile ground origin: $fullPath; complete $($reference.width)x$($reference.height) ground footprint is centered at ($($reference.centerX), $($reference.centerY)), not (0, 0). Whole-template translation requires confirmation; do not infer the center from decorative geometry."
    }
    $script:GroundGridWarnings[$key] = $true
}

Export-ModuleMember -Function Get-ZMTileGroundBases, Get-ZMTileGroundGridIssues, Get-ZMTileGroundReference, Repair-ZMTileGroundGridText, Move-ZMTileGroundOriginText, Write-ZMTileGroundGridWarnings
