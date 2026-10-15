Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'skybox_models.psm1')
Import-Module (Join-Path $PSScriptRoot 'tile_ground_grid.psm1')

if (-not ('ZombieSim.Infill.Geometry' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Linq;
namespace ZombieSim.Infill {
    public struct Point {
        public double X, Y;
        public Point(double x, double y) { X = x; Y = y; }
    }
    public static class Geometry {
        static double Cross(Point a, Point b, Point c) {
            double x=b.X-a.X,y=b.Y-a.Y,u=c.X-a.X,v=c.Y-a.Y;
            double determinant=x*v-y*u;
            // Bound subtraction/product roundoff, not a world-space seam tolerance.
            double error=8*Math.Pow(2,-52)*(
                (Math.Abs(b.X)+Math.Abs(a.X))*Math.Abs(v)+
                (Math.Abs(c.Y)+Math.Abs(a.Y))*Math.Abs(x)+
                (Math.Abs(b.Y)+Math.Abs(a.Y))*Math.Abs(u)+
                (Math.Abs(c.X)+Math.Abs(a.X))*Math.Abs(y)+Math.Abs(x*v)+Math.Abs(y*u));
            return Math.Abs(determinant)<=error ? 0 : determinant;
        }
        public static Point[] Hull(Point[] points) {
            var p = points.Distinct().OrderBy(v=>v.X).ThenBy(v=>v.Y).ToArray();
            if (p.Length < 3) return p;
            var hull = new List<Point>();
            foreach(var v in p) {
                while(hull.Count >= 2 && Cross(hull[hull.Count-2], hull[hull.Count-1], v) <= 0) hull.RemoveAt(hull.Count-1);
                hull.Add(v);
            }
            int lower = hull.Count;
            for(int i=p.Length-2;i>=0;i--) {
                while(hull.Count > lower && Cross(hull[hull.Count-2], hull[hull.Count-1], p[i]) <= 0) hull.RemoveAt(hull.Count-1);
                hull.Add(p[i]);
            }
            hull.RemoveAt(hull.Count-1);
            return hull.ToArray();
        }
        public static bool Intersects(Point[] polygon, double x, double y, double width, double height) {
            if(polygon.Length < 3) return false;
            var box = new [] { new Point(x,y), new Point(x+width,y), new Point(x+width,y+height), new Point(x,y+height) };
            return Intersects(polygon, box);
        }
        public static bool Intersects(Point[] polygon, Point[] box) {
            if(polygon.Length < 3 || box.Length < 3) return false;
            var axes = new List<Point>();
            foreach(var shape in new [] {polygon,box})
                for(int i=0;i<shape.Length;i++) {
                    var a=shape[i]; var b=shape[(i+1)%shape.Length];
                    axes.Add(b.X==a.X ? new Point(1,0) : b.Y==a.Y ? new Point(0,1) : new Point(-(b.Y-a.Y), b.X-a.X));
                }
            foreach(var axis in axes) {
                double minA=double.PositiveInfinity,maxA=double.NegativeInfinity,minB=minA,maxB=maxA;
                foreach(var p in polygon) { double d=p.X*axis.X+p.Y*axis.Y; minA=Math.Min(minA,d); maxA=Math.Max(maxA,d); }
                foreach(var p in box) { double d=p.X*axis.X+p.Y*axis.Y; minB=Math.Min(minB,d); maxB=Math.Max(maxB,d); }
                double roundoff=8*Math.Pow(2,-52)*Math.Max(
                    Math.Max(Math.Abs(minA),Math.Abs(maxA)),Math.Max(Math.Abs(minB),Math.Abs(maxB)));
                if(maxA-minB<=roundoff || maxB-minA<=roundoff) return false;
            }
            return true;
        }
        public static double Area(Point[] p) {
            double area=0;
            for(int i=1;i+1<p.Length;i++) area+=Cross(p[0],p[i],p[i+1]);
            return Math.Abs(area)/2;
        }
        static bool SharesEdge(Point[] a, Point[] b) {
            for(int i=0;i<a.Length;i++) {
                var p=a[i]; var q=a[(i+1)%a.Length];
                bool useX=Math.Abs(q.X-p.X)>=Math.Abs(q.Y-p.Y);
                double low=Math.Min(useX?p.X:p.Y,useX?q.X:q.Y);
                double high=Math.Max(useX?p.X:p.Y,useX?q.X:q.Y);
                if(low==high) continue;
                for(int j=0;j<b.Length;j++) {
                    var r=b[j]; var s=b[(j+1)%b.Length];
                    if(Cross(p,q,r)!=0 || Cross(p,q,s)!=0) continue;
                    double otherLow=Math.Min(useX?r.X:r.Y,useX?s.X:s.Y);
                    double otherHigh=Math.Max(useX?r.X:r.Y,useX?s.X:s.Y);
                    if(Math.Min(high,otherHigh)>Math.Max(low,otherLow)) return true;
                }
            }
            return false;
        }
        static bool IntegerRectangle(Point[] p) {
            if(p.Length!=4) return false;
            double x=p.Min(v=>v.X),y=p.Min(v=>v.Y);
            double width=p.Max(v=>v.X)-x,height=p.Max(v=>v.Y)-y;
            if(width>5760 || height>5760) return false;
            return p.All(v=>v.X==Math.Round(v.X) && v.Y==Math.Round(v.Y)) &&
                Area(p)==width*height;
        }
        public static Point[][] MergeRectangles(Point[][] polygons, Point[][] obstacles) {
            var pieces=new List<Point[]>(polygons);
            bool changed=true;
            while(changed) {
                changed=false;
                for(int i=0;i<pieces.Count && !changed;i++) {
                    for(int j=i+1;j<pieces.Count;j++) {
                        var a=pieces[i]; var b=pieces[j];
                        if(!IntegerRectangle(a) || !IntegerRectangle(b)) continue;
                        if(!SharesEdge(a,b) || Intersects(a,b)) continue;
                        var hull=Hull(a.Concat(b).ToArray());
                        if(!IntegerRectangle(hull)) continue;
                        double expected=Area(a)+Area(b);
                        double error=16*Math.Pow(2,-52)*expected*(a.Length+b.Length);
                        if(Math.Abs(Area(hull)-expected)>error) continue;
                        if(obstacles.Any(p=>Intersects(hull,p))) continue;
                        pieces[i]=hull;
                        pieces.RemoveAt(j);
                        changed=true;
                        break;
                    }
                }
            }
            return pieces.ToArray();
        }
        static Point[] Clip(Point[] p, Point a, Point b, bool inside) {
            var result=new List<Point>();
            for(int i=0;i<p.Length;i++) {
                var from=p[i]; var to=p[(i+1)%p.Length];
                double f=Cross(a,b,from),t=Cross(a,b,to);
                bool keepF=inside ? f>=0 : f<=0, keepT=inside ? t>=0 : t<=0;
                if(keepF) result.Add(from);
                if(keepF!=keepT) {
                    double fraction=f/(f-t);
                    result.Add(new Point(from.X+(to.X-from.X)*fraction,from.Y+(to.Y-from.Y)*fraction));
                }
            }
            return result.Count>=3 ? Hull(result.ToArray()) : new Point[0];
        }
        public static Point[][] Uncovered(Point[][] obstacles, double x, double y, double width, double height) {
            var pieces=new List<Point[]> { new [] {new Point(x,y),new Point(x+width,y),new Point(x+width,y+height),new Point(x,y+height)} };
            foreach(var obstacle in obstacles) {
                if(!Intersects(obstacle,x,y,width,height)) continue;
                var next=new List<Point[]>();
                foreach(var piece in pieces) {
                    var remaining=piece;
                    for(int i=0;i<obstacle.Length && remaining.Length>=3;i++) {
                        var a=obstacle[i]; var b=obstacle[(i+1)%obstacle.Length];
                        var outside=Clip(remaining,a,b,false);
                        if(outside.Length>=3 && Area(outside)>0) next.Add(outside);
                        remaining=Clip(remaining,a,b,true);
                    }
                }
                pieces=next;
                if(pieces.Count==0) break;
            }
            return pieces.ToArray();
        }
    }
}
'@
}

function Get-ZMInfillObstacles {
    param([string]$Path, [object]$Origin, [int]$Yaw)

    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($Path))
    foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            $solidPoints = [System.Collections.Generic.List[object]]::new()
            $regionPoints = [System.Collections.Generic.List[object]]::new()
            $bottom = -$Origin.z
            $top = 32 - $Origin.z
            foreach ($side in @($solid.Children | Where-Object Name -eq side)) {
                $winding = $side.Child('vertices_plus')
                if ($null -eq $winding) { throw "Infill requires saved windings: $Path side $($side.Get('id'))." }
                $vertices = @($winding.GetAll('v') | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_) })
                if ($vertices.Count -lt 3) { throw "Incomplete infill winding: $Path side $($side.Get('id'))." }
                foreach ($vertex in $vertices) {
                    foreach ($value in @($vertex.X, $vertex.Y, $vertex.Z)) {
                        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw "Non-finite infill winding: $Path side $($side.Get('id'))." }
                    }
                    $solidPoints.Add($vertex)
                }
                $displaced = $null -ne $side.Child('dispinfo')
                for ($index = 0; $index -lt $vertices.Count; $index++) {
                    $a = $vertices[$index]
                    $b = $vertices[($index + 1) % $vertices.Count]
                    if (($a.Z -ge $bottom -and $a.Z -le $top) -or $displaced) { $regionPoints.Add($a) }
                    foreach ($height in @($bottom, $top)) {
                        if (($a.Z -lt $height -and $b.Z -gt $height) -or ($b.Z -lt $height -and $a.Z -gt $height)) {
                            $fraction = ($height - $a.Z) / ($b.Z - $a.Z)
                            $regionPoints.Add([ZombieSim.Skybox.Vec3]::new(
                                $a.X + ($b.X - $a.X) * $fraction,
                                $a.Y + ($b.Y - $a.Y) * $fraction,
                                $height
                            ))
                        }
                    }
                }
            }
            if ($solidPoints.Count -lt 3) { continue }
            $boundsZ = $solidPoints | Measure-Object Z -Minimum -Maximum
            if ($boundsZ.Minimum + $Origin.z -ge 32 -or $boundsZ.Maximum + $Origin.z -le 0) { continue }
            if ($regionPoints.Count -lt 3) { continue }
            $boundsX = $regionPoints | Measure-Object X -Minimum -Maximum
            $boundsY = $regionPoints | Measure-Object Y -Minimum -Maximum
            $corners = @(
                [ZombieSim.Infill.Point]::new($boundsX.Minimum, $boundsY.Minimum),
                [ZombieSim.Infill.Point]::new($boundsX.Maximum, $boundsY.Minimum),
                [ZombieSim.Infill.Point]::new($boundsX.Maximum, $boundsY.Maximum),
                [ZombieSim.Infill.Point]::new($boundsX.Minimum, $boundsY.Maximum)
            )
            $xy = @($corners | ForEach-Object {
                $corner = $_
                switch ($Yaw) {
                    0 { $x = $corner.X; $y = $corner.Y }
                    90 { $x = -$corner.Y; $y = $corner.X }
                    180 { $x = -$corner.X; $y = -$corner.Y }
                    270 { $x = $corner.Y; $y = -$corner.X }
                    default { throw "Unsupported infill yaw: $Yaw" }
                }
                [ZombieSim.Infill.Point]::new($x + $Origin.x, $y + $Origin.y)
            })
            $polygon = [ZombieSim.Infill.Geometry]::Hull([ZombieSim.Infill.Point[]]$xy)
            if ($polygon.Count -ge 3) {
                [pscustomobject]@{ source = $Path; solidId = $solid.Get('id'); polygon = $polygon }
            }
        }
    }
}

function Get-ZMInfillGroundCoverage {
    param([string]$Path, [object]$Origin, [int]$Yaw)

    if ($Yaw -notin @(0, 90, 180, 270)) { throw "Unsupported ground coverage yaw: $Yaw" }
    $bases = @(Get-ZMTileGroundBases $Path -Partitioned)
    $rectangles = [System.Collections.Generic.List[object]]::new()
    foreach ($base in $bases) {
        $rectangles.Add([pscustomobject]@{
            minX = $base.bounds.X.Minimum; maxX = $base.bounds.X.Maximum
            minY = $base.bounds.Y.Minimum; maxY = $base.bounds.Y.Maximum
            solidId = $base.solid.Get('id'); role = 'recognized_ground'
        })
    }
    # Unknown ground and authored depressions require review, not generated cut-out brushes.
    $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($Path))
    $groundSolidIds = @{}
    foreach ($base in $bases) { $groundSolidIds[$base.solid.Get('id')] = $true }
    foreach ($obstacle in @(Get-ZMInfillObstacles $Path $Origin $Yaw)) {
        if ($groundSolidIds.ContainsKey($obstacle.solidId)) { continue }
        [pscustomobject]@{
            source = $obstacle.source; solidId = $obstacle.solidId
            role = 'authored_geometry_bounds'; polygon = $obstacle.polygon
        }
    }
    $protected = $false
    foreach ($owner in @($tree.Child('world')) + @($tree.Children | Where-Object Name -eq entity)) {
        foreach ($solid in @($owner.Children | Where-Object Name -eq solid)) {
            $sides = @($solid.Children | Where-Object Name -eq side)
            if (@($sides | Where-Object { $null -ne $_.Child('dispinfo') }).Count) { $protected = $true }
            $points = @($sides | ForEach-Object { $_.Child('vertices_plus') } | Where-Object { $null -ne $_ } |
                ForEach-Object { $_.GetAll('v') } | ForEach-Object { [ZombieSim.Skybox.Vec3]::Parse($_) })
            if ($points.Count -gt 0 -and @($points | Where-Object { $_.Z + $Origin.z -gt 0 }).Count -eq 0) { $protected = $true }
        }
    }
    if ($bases.Count -eq 0 -or $protected) {
        $name = [IO.Path]::GetFileNameWithoutExtension($Path)
        $width = 640; $height = 640
        if ($name -match '_(\d+)x(\d+)$') { $width *= [int]$Matches[1]; $height *= [int]$Matches[2] }
        elseif ($name -match '_(\d+)x$') { $width *= [int]$Matches[1]; $height = $width }
        elseif ((Split-Path -Leaf (Split-Path -Parent $Path)) -eq 'motorway_3x1') { $width = 1920 }
        $rectangles.Add([pscustomobject]@{
            minX = -$width / 2; maxX = $width / 2; minY = -$height / 2; maxY = $height / 2
            solidId = $null; role = 'reserved_nonstandard_ground_requires_review'
        })
        Write-Warning "Ground infill reserves the nominal footprint for nonstandard or protected ground: $Path. No polygon filler will be generated."
    }
    foreach ($rectangle in $rectangles) {
        $points = @(foreach ($x in @($rectangle.minX, $rectangle.maxX)) {
            foreach ($y in @($rectangle.minY, $rectangle.maxY)) {
                if ($Yaw -eq 0) { $px = $x; $py = $y }
                elseif ($Yaw -eq 90) { $px = -$y; $py = $x }
                elseif ($Yaw -eq 180) { $px = -$x; $py = -$y }
                else { $px = $y; $py = -$x }
                [ZombieSim.Infill.Point]::new($px + $Origin.x, $py + $Origin.y)
            }
        })
        [pscustomobject]@{
            source = $Path; solidId = $rectangle.solidId; role = $rectangle.role
            polygon = [ZombieSim.Infill.Geometry]::Hull([ZombieSim.Infill.Point[]]$points)
        }
    }
}

function Get-ZMInfillPatchName {
    param([double]$Width, [double]$Height)

    foreach ($dimension in @($Width, $Height)) {
        if ($dimension -notin @(4, 8, 16, 32, 64, 128, 256, 512)) { throw "Invalid infill patch dimension: $dimension. Extra patches require powers of two from4 through512." }
    }
    $w = $Width.ToString('R', [Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
    $h = $Height.ToString('R', [Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
    return "terrain\infill\tile_ground_patch_u${w}_u${h}.vmf"
}

function Get-ZMInfillRectanglePieces {
    param([object]$Gap)

    $minX = [double]$Gap.minX; $minY = [double]$Gap.minY
    $width = [double]$Gap.width; $height = [double]$Gap.height
    foreach ($value in @($minX, $minY, $width, $height)) {
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw 'Non-finite rectangular ground boundary.' }
    }
    if ($width -le 0 -or $height -le 0 -or $width -gt 5760 -or $height -gt 5760) { throw 'Ground gap must be a positive rectangle bounded by the cell frame.' }
    $pieces = [Collections.Generic.List[object]]::new()
    $unfilled = [Collections.Generic.List[object]]::new()
    if (@(@($minX, $minY, $width, $height) | Where-Object { $_ -ne [Math]::Round($_) }).Count) {
        $left = [Math]::Ceiling($minX); $bottom = [Math]::Ceiling($minY)
        $right = [Math]::Floor($minX + $width); $top = [Math]::Floor($minY + $height)
        if ($right -le $left -or $top -le $bottom) {
            $unfilled.Add([pscustomobject]@{ minX = $minX; minY = $minY; width = $width; height = $height; status = 'below_u4_left_on_default_floor' })
        } else {
            $inner = Get-ZMInfillRectanglePieces ([pscustomobject]@{ minX = $left; minY = $bottom; width = $right - $left; height = $top - $bottom })
            foreach ($piece in $inner.pieces) { $pieces.Add($piece) }
            foreach ($piece in $inner.unfilled) { $unfilled.Add($piece) }
            foreach ($strip in @(
                [pscustomobject]@{ minX = $minX; minY = $minY; width = $left - $minX; height = $height },
                [pscustomobject]@{ minX = $right; minY = $minY; width = $minX + $width - $right; height = $height },
                [pscustomobject]@{ minX = $left; minY = $minY; width = $right - $left; height = $bottom - $minY },
                [pscustomobject]@{ minX = $left; minY = $top; width = $right - $left; height = $minY + $height - $top }
            )) {
                if ($strip.width -le 0 -or $strip.height -le 0) { continue }
                $strip | Add-Member -NotePropertyName status -NotePropertyValue 'below_u4_left_on_default_floor'
                $unfilled.Add($strip)
            }
        }
    } else {
        $standard = if ($width -eq 640 -and $height -eq 640) { 'terrain\infill\tile_ground_full.vmf' }
            elseif ($width -eq 320 -and $height -eq 320) { 'terrain\infill\tile_ground_quarter.vmf' }
            elseif (($width -eq 320 -and $height -eq 640) -or ($width -eq 640 -and $height -eq 320)) { 'terrain\infill\tile_ground_half.vmf' }
            else { $null }
        if ($null -ne $standard) {
            $pieces.Add([pscustomobject]@{
                minX = $minX; minY = $minY; width = $width; height = $height; template = $standard
                yaw = $(if ($width -eq 640 -and $height -eq 320) { 90 } else { 0 })
            })
        } elseif ($width % 320 -eq 0 -and $height % 320 -eq 0) {
            for ($y = 0.0; $y -lt $height; $y += 640) {
                for ($x = 0.0; $x -lt $width; $x += 640) {
                    $w = [Math]::Min(640, $width - $x); $h = [Math]::Min(640, $height - $y)
                    $template = if ($w -eq 640 -and $h -eq 640) { 'terrain\infill\tile_ground_full.vmf' }
                        elseif ($w -eq 320 -and $h -eq 320) { 'terrain\infill\tile_ground_quarter.vmf' }
                        else { 'terrain\infill\tile_ground_half.vmf' }
                    $pieces.Add([pscustomobject]@{
                        minX = $minX + $x; minY = $minY + $y; width = $w; height = $h; template = $template
                        yaw = $(if ($w -eq 640 -and $h -eq 320) { 90 } else { 0 })
                    })
                }
            }
        } else {
            $axes = @()
            foreach ($dimension in @($width, $height)) {
                $segments = [Collections.Generic.List[object]]::new()
                $offset = 0.0
                foreach ($size in @(512, 256, 128, 64, 32, 16, 8, 4)) {
                    while ($dimension - $offset -ge $size) {
                        $segments.Add([pscustomobject]@{ offset = $offset; size = $size })
                        $offset += $size
                    }
                }
                if ($dimension -gt $offset) { $segments.Add([pscustomobject]@{ offset = $offset; size = $dimension - $offset }) }
                $axes += ,$segments.ToArray()
            }
            foreach ($x in $axes[0]) {
                foreach ($y in $axes[1]) {
                    $piece = [pscustomobject]@{ minX = $minX + $x.offset; minY = $minY + $y.offset; width = $x.size; height = $y.size }
                    if ($x.size -lt 4 -or $y.size -lt 4) {
                        $piece | Add-Member -NotePropertyName status -NotePropertyValue 'below_u4_left_on_default_floor'
                        $unfilled.Add($piece)
                    } else {
                        $piece | Add-Member -NotePropertyName template -NotePropertyValue (Get-ZMInfillPatchName $x.size $y.size)
                        $piece | Add-Member -NotePropertyName yaw -NotePropertyValue 0
                        $pieces.Add($piece)
                    }
                }
            }
        }
    }
    return [pscustomobject]@{ pieces = @($pieces); unfilled = @($unfilled) }
}

function Get-ZMInfillShape {
    param([object]$Gap)

    $worldPoints = @($Gap.polygon | ForEach-Object {
        [ZombieSim.Infill.Point]::new([double]::Parse([string]$_.X, [Globalization.CultureInfo]::InvariantCulture), [double]::Parse([string]$_.Y, [Globalization.CultureInfo]::InvariantCulture))
    })
    $rangeX = $worldPoints | Measure-Object X -Minimum -Maximum
    $rangeY = $worldPoints | Measure-Object Y -Minimum -Maximum
    $centerX = $rangeX.Minimum + ($rangeX.Maximum - $rangeX.Minimum) / 2
    $centerY = $rangeY.Minimum + ($rangeY.Maximum - $rangeY.Minimum) / 2
    $points = [ZombieSim.Infill.Point[]]@($worldPoints | ForEach-Object {
        [ZombieSim.Infill.Point]::new($_.X - $centerX, $_.Y - $centerY)
    })
    $polygon = [ZombieSim.Infill.Geometry]::Hull($points)
    if ($polygon.Count -lt 3 -or [ZombieSim.Infill.Geometry]::Area($polygon) -le 0) { throw 'Infill shape requires a nondegenerate convex polygon.' }
    $identity = ($polygon | ForEach-Object {
        '{0},{1}' -f $_.X.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $_.Y.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    }) -join ';'
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    return [pscustomobject]@{
        template = "terrain\infill\tile_ground_shape_$hash.vmf"
        polygon = $polygon
        origin = [pscustomobject]@{
            x = $centerX.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            y = $centerY.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
            z = 0
        }
    }
}

function New-ZMInfillShapeVmf {
    param([string]$BaseText, [object[]]$Polygon, [switch]$LegacyWinding)

    $worldStart = [regex]::Match($BaseText, '(?m)^world\r?$')
    $camerasStart = [regex]::Match($BaseText, '(?m)^cameras\r?$')
    if (-not $worldStart.Success -or -not $camerasStart.Success) { throw 'Ground source requires world/cameras blocks.' }
    $baseTree = [ZombieSim.Skybox.KeyValuesParser]::Parse($BaseText)
    $baseSolid = @($baseTree.Child('world').Children | Where-Object Name -eq solid)[0]
    $top = @($baseSolid.Children | Where-Object Name -eq side)[0]
    $bottom = @($baseSolid.Children | Where-Object Name -eq side)[1]
    $faces = [System.Collections.Generic.List[object]]::new()
    $topPoints = $Polygon.Clone()
    [array]::Reverse($topPoints)
    if ($LegacyWinding) { $Polygon = $topPoints }
    $faces.Add([pscustomobject]@{ points = @($topPoints | ForEach-Object { [ZombieSim.Skybox.Vec3]::new($_.X, $_.Y, 32) }); material = $top.Get('material'); u = $top.Get('uaxis'); v = $top.Get('vaxis') })
    $faces.Add([pscustomobject]@{ points = @($Polygon | ForEach-Object { [ZombieSim.Skybox.Vec3]::new($_.X, $_.Y, 0) }); material = $bottom.Get('material'); u = $bottom.Get('uaxis'); v = $bottom.Get('vaxis') })
    for ($index = 0; $index -lt $Polygon.Count; $index++) {
        $a = $Polygon[$index]; $b = $Polygon[($index + 1) % $Polygon.Count]
        $faces.Add([pscustomobject]@{
            points = @([ZombieSim.Skybox.Vec3]::new($a.X, $a.Y, 32), [ZombieSim.Skybox.Vec3]::new($b.X, $b.Y, 32), [ZombieSim.Skybox.Vec3]::new($b.X, $b.Y, 0), [ZombieSim.Skybox.Vec3]::new($a.X, $a.Y, 0))
            material = $bottom.Get('material')
            u = $(if ([Math]::Abs($b.X - $a.X) -ge [Math]::Abs($b.Y - $a.Y)) { '[1 0 0 256] 0.25' } else { '[0 1 0 256] 0.25' })
            v = '[0 0 -1 256] 0.25'
        })
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]@('world', '{', '    "id" "1"', '    "classname" "worldspawn"', '    "mapversion" "1"', '    "skyname" "sky_day01_01"', '    solid', '    {', '        "id" "2"'))
    $id = 3
    foreach ($face in $faces) {
        $vertices = @($face.points | ForEach-Object {
            '{0} {1} {2}' -f $_.X.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $_.Y.ToString('R', [Globalization.CultureInfo]::InvariantCulture), $_.Z.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        })
        $lines.AddRange([string[]]@('        side', '        {', ('            "id" "{0}"' -f $id), ('            "plane" "({0}) ({1}) ({2})"' -f $vertices[0], $vertices[1], $vertices[2]), '            vertices_plus', '            {'))
        foreach ($vertex in $vertices) { $lines.Add('                "v" "' + $vertex + '"') }
        $lines.AddRange([string[]]@('            }', ('            "material" "{0}"' -f $face.material), ('            "uaxis" "{0}"' -f $face.u), ('            "vaxis" "{0}"' -f $face.v), '            "rotation" "0"', '            "lightmapscale" "16"', '            "smoothing_groups" "0"', '        }'))
        $id++
    }
    $lines.AddRange([string[]]@('    }', '}'))
    return $BaseText.Substring(0, $worldStart.Index) + ($lines -join [Environment]::NewLine) + [Environment]::NewLine + $BaseText.Substring($camerasStart.Index)
}

function New-ZMInfillRectangleVmf {
    param([string]$BaseText, [double]$Width, [double]$Height)

    [regex]::Replace($BaseText, '(?m)("(?:plane|v)" ")([^"]+)(")', {
        param($match)
        $coordinates = [regex]::Replace($match.Groups[2].Value, '(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)', {
            param($point)
            '{0} {1} {2}' -f ([double]([double]::Parse($point.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) / 640 * $Width)).ToString('R', [Globalization.CultureInfo]::InvariantCulture),
                ([double]([double]::Parse($point.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) / 640 * $Height)).ToString('R', [Globalization.CultureInfo]::InvariantCulture), $point.Groups[3].Value
        })
        $match.Groups[1].Value + $coordinates + $match.Groups[3].Value
    })
}

function Set-ZMInspectionTerrainInfill {
    param([object]$Recipe, [string]$TemplateDirectory, [object[]]$BorderPlacements, [object[]]$OuterPlacements, [switch]$SizedPatches, [switch]$CompletePatches, [switch]$MeasureCompletePatches)

    $inspection = @(foreach ($name in @('motorwayCellInspection', 'motorwayAssembly')) { if ($null -ne $Recipe.PSObject.Properties[$name] -and $Recipe.$name.schemaVersion -eq 2) { $Recipe.$name } })
    if ($inspection.Count -ne 1) { throw 'Complex terrain infill requires one schema-2 motorway contract.' }
    $inspection = $inspection[0]
    # Omitted skybox-ocean outer bands keep their beach; infill stays inside the retained 2240 boundary there.
    $ocean = @(if ($null -ne $Recipe.PSObject.Properties['skyboxOceanSides']) { @($Recipe.skyboxOceanSides) })
    $obstacles = [System.Collections.Generic.List[object]]::new()
    $sources = @($inspection.assemblies)
    foreach ($placement in @($Recipe.tilePlacements | Where-Object { $_.role -ne 'motorway_external_occupied' }) + $BorderPlacements + $OuterPlacements) {
        $sources += [pscustomobject]@{
            template = $placement.template; yaw = $placement.rotationYaw
            origin = [pscustomobject]@{ x = ($placement.tileX - 2) * 640; y = (2 - $placement.tileY) * 640; z = 0 }
        }
    }
    foreach ($source in $sources) {
        foreach ($obstacle in @(Get-ZMInfillGroundCoverage (Join-Path $TemplateDirectory $source.template) $source.origin $source.yaw)) { $obstacles.Add($obstacle) }
    }
    $available = @{}
    $blocked = 0
    $partialGaps = [System.Collections.Generic.List[object]]::new()
    $polygons = [ZombieSim.Infill.Point[][]]@($obstacles | ForEach-Object { ,$_.polygon })
    foreach ($y in 0..17) {
        foreach ($x in 0..17) {
            $minX = -2880 + $x * 320; $minY = -2880 + $y * 320
            if (($ocean -contains 'W' -and $minX -lt -2240) -or ($ocean -contains 'E' -and $minX + 320 -gt 2240) -or
                ($ocean -contains 'S' -and $minY -lt -2240) -or ($ocean -contains 'N' -and $minY + 320 -gt 2240)) { continue }
            $intersects = $false
            foreach ($obstacle in $obstacles) {
                if ([ZombieSim.Infill.Geometry]::Intersects($obstacle.polygon, $minX, $minY, 320, 320)) { $intersects = $true; break }
            }
            if ($intersects) {
                $blocked++
                foreach ($gap in [ZombieSim.Infill.Geometry]::Uncovered($polygons, $minX, $minY, 320, 320)) {
                    $rangeX = $gap | Measure-Object X -Minimum -Maximum
                    $rangeY = $gap | Measure-Object Y -Minimum -Maximum
                    $area = [ZombieSim.Infill.Geometry]::Area($gap)
                    $width = $rangeX.Maximum - $rangeX.Minimum; $height = $rangeY.Maximum - $rangeY.Minimum
                    $partialGaps.Add([pscustomobject]@{
                        minX = $rangeX.Minimum; minY = $rangeY.Minimum; width = $width; height = $height; area = $area
                        rectangular = $area -eq $width * $height
                        polygon = @($gap | ForEach-Object {
                            [pscustomobject]@{ X = $_.X.ToString('R', [Globalization.CultureInfo]::InvariantCulture); Y = $_.Y.ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
                        })
                        status = 'unfilled_partial_slot_requires_sized_source_or_approved_clipping'
                    })
                }
            } else { $available["$x,$y"] = $true }
        }
    }
    if (($CompletePatches -or $MeasureCompletePatches) -and [IO.Path]::GetFileName($inspection.template) -ne 'tile_motorway_corner_5x3.vmf') {
        foreach ($y in 0..17) {
            foreach ($x in 0..17) {
                if (-not $available.ContainsKey("$x,$y")) { continue }
                $minX = -2880 + $x * 320; $minY = -2880 + $y * 320
                $partialGaps.Add([pscustomobject]@{
                    minX = $minX; minY = $minY; width = 320; height = 320; area = 102400; rectangular = $true
                    polygon = @(
                        [pscustomobject]@{ X = "$minX"; Y = "$minY" },
                        [pscustomobject]@{ X = "$($minX + 320)"; Y = "$minY" },
                        [pscustomobject]@{ X = "$($minX + 320)"; Y = "$($minY + 320)" },
                        [pscustomobject]@{ X = "$minX"; Y = "$($minY + 320)" }
                    )
                    status = 'unfilled_partial_slot_requires_sized_source_or_approved_clipping'
                })
            }
        }
        $available.Clear()
    }
    $unmergedGapCount = $partialGaps.Count
    if (($CompletePatches -or $MeasureCompletePatches) -and [IO.Path]::GetFileName($inspection.template) -ne 'tile_motorway_corner_5x3.vmf') {
        $baseText = [IO.File]::ReadAllText((Join-Path $TemplateDirectory 'terrain\tile_grass.vmf'))
        $mergeable = [System.Collections.Generic.List[ZombieSim.Infill.Point[]]]::new()
        $retained = [System.Collections.Generic.List[object]]::new()
        foreach ($gap in $partialGaps) {
            $integer = $gap.rectangular -and @($gap.polygon | Where-Object {
                [double]$_.X -ne [Math]::Round([double]$_.X) -or [double]$_.Y -ne [Math]::Round([double]$_.Y)
            }).Count -eq 0
            if (-not $integer) {
                $gap.status = 'fractional_ground_boundary_requires_source_review'
                $retained.Add($gap)
                continue
            }
            $authored = $false
            $candidate = Get-ZMInfillRectanglePieces $gap
            foreach ($piece in $candidate.pieces) {
                $path = Join-Path $TemplateDirectory $piece.template
                $localWidth = if ($piece.yaw -eq 90) { $piece.height } else { $piece.width }
                $localHeight = if ($piece.yaw -eq 90) { $piece.width } else { $piece.height }
                $expected = New-ZMInfillRectangleVmf $baseText $localWidth $localHeight
                if ((Test-Path -LiteralPath ([IO.Path]::ChangeExtension($path, '.vmx'))) -or
                    ((Test-Path -LiteralPath $path) -and [IO.File]::ReadAllText($path) -cne $expected)) { $authored = $true }
            }
            if ($authored) { $retained.Add($gap); continue }
            $mergeable.Add([ZombieSim.Infill.Point[]]@($gap.polygon | ForEach-Object {
                [ZombieSim.Infill.Point]::new([double]::Parse([string]$_.X, [Globalization.CultureInfo]::InvariantCulture), [double]::Parse([string]$_.Y, [Globalization.CultureInfo]::InvariantCulture))
            }))
        }
        $partialGaps = $retained
        foreach ($gap in [ZombieSim.Infill.Geometry]::MergeRectangles($mergeable.ToArray(), $polygons)) {
            $rangeX = $gap | Measure-Object X -Minimum -Maximum
            $rangeY = $gap | Measure-Object Y -Minimum -Maximum
            $width = $rangeX.Maximum - $rangeX.Minimum; $height = $rangeY.Maximum - $rangeY.Minimum
            $area = [ZombieSim.Infill.Geometry]::Area($gap)
            $partialGaps.Add([pscustomobject]@{
                minX = $rangeX.Minimum; minY = $rangeY.Minimum; width = $width; height = $height; area = $area
                rectangular = $area -eq $width * $height
                polygon = @($gap | ForEach-Object {
                    [pscustomobject]@{ X = $_.X.ToString('R', [Globalization.CultureInfo]::InvariantCulture); Y = $_.Y.ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
                })
                status = 'unfilled_partial_slot_requires_sized_source_or_approved_clipping'
            })
        }
    }
    $placements = [System.Collections.Generic.List[object]]::new()
    foreach ($y in 0..17) {
        foreach ($x in 0..17) {
            $key = "$x,$y"
            if (-not $available.ContainsKey($key)) { continue }
            $yaw = 0; $width = 320; $height = 320
            $template = 'terrain\infill\tile_ground_quarter.vmf'
            if ($x -lt 17 -and $y -lt 17 -and $available.ContainsKey("$($x + 1),$y") -and
                $available.ContainsKey("$x,$($y + 1)") -and $available.ContainsKey("$($x + 1),$($y + 1)")) {
                $width = 640; $height = 640
                $available.Remove("$($x + 1),$y"); $available.Remove("$x,$($y + 1)"); $available.Remove("$($x + 1),$($y + 1)")
                $template = 'terrain\infill\tile_ground_full.vmf'
            } elseif ($y -lt 17 -and $available.ContainsKey("$x,$($y + 1)")) {
                $height = 640; $available.Remove("$x,$($y + 1)")
                $template = 'terrain\infill\tile_ground_half.vmf'
            } elseif ($x -lt 17 -and $available.ContainsKey("$($x + 1),$y")) {
                $width = 640; $yaw = 90; $available.Remove("$($x + 1),$y")
                $template = 'terrain\infill\tile_ground_half.vmf'
            }
            $available.Remove($key)
            $placements.Add([pscustomobject]@{
                template = $template; yaw = $yaw; width = $width; height = $height
                origin = [pscustomobject]@{ x = -2880 + $x * 320 + $width / 2; y = -2880 + $y * 320 + $height / 2; z = 0 }
                owner = "infill:$x,$y"
            })
        }
    }
    $fingerprints = @{}
    $unfilled = [Collections.Generic.List[object]]::new()
    if (($SizedPatches -or $MeasureCompletePatches) -and [IO.Path]::GetFileName($inspection.template) -ne 'tile_motorway_corner_5x3.vmf') {
        $index = 0
        foreach ($gap in $partialGaps | Where-Object rectangular) {
            $split = Get-ZMInfillRectanglePieces $gap
            foreach ($piece in $split.pieces) {
                $placements.Add([pscustomobject]@{
                    template = $piece.template; yaw = $piece.yaw; width = $piece.width; height = $piece.height
                    origin = [pscustomobject]@{ x = $piece.minX + $piece.width / 2; y = $piece.minY + $piece.height / 2; z = 0 }
                    owner = "infill:patch$index"
                })
                $index++
            }
            foreach ($piece in $split.unfilled) { $unfilled.Add($piece) }
            $gap.status = if ($split.unfilled.Count) { 'partly_filled_standard_rectangles_remainder_reported' } else { 'filled_by_standard_rectangles' }
        }
    }
    $requiredRectangles = @($placements)
    if ($MeasureCompletePatches) { $placements.Clear() }
    $templates = @('terrain\infill\tile_ground_half.vmf', 'terrain\infill\tile_ground_quarter.vmf') + @($placements | ForEach-Object template) | Sort-Object -Unique
    $unresolved = @($partialGaps | Where-Object status -eq 'fractional_ground_boundary_requires_source_review')
    if ($unresolved.Count) { Write-Warning "Ground infill: $($unresolved.Count) fractional boundaries require source review for $($inspection.template); no fractional or polygon sources emitted." }
    if ($unfilled.Count) { Write-Warning "Ground infill: $($unfilled.Count) sub4 remainders left on the default floor for $($inspection.template); no sub4 sources emitted." }
    foreach ($template in $templates) {
        $path = Join-Path $TemplateDirectory $template
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing editable infill base template: $path. Run create_terrain_infill_templates.ps1 first." }
        $fingerprints[$template] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $tree = [ZombieSim.Skybox.KeyValuesParser]::Parse([IO.File]::ReadAllText($path))
        $base = @($tree.Child('world').Children | Where-Object Name -eq solid | Select-Object -First 1)
        if ($base.Count -ne 1) { throw "Editable infill template has lost its base ground brush: $path" }
        $corners = @{}
        $dimensions = @($placements | Where-Object template -eq $template | Select-Object -First 1)
        if ($template -like '*tile_ground_shape_*' -or $template -match 'patch_u[^\\]*p') { throw "Retired polygon/decimal ground source selected: $template" }
        $halfX = if ($template -like '*_full.vmf') { 320 } elseif ($template -like '*_half.vmf' -or $template -like '*_quarter.vmf') { 160 } else { [double]$dimensions[0].width / 2 }
        $halfY = if ($template -like '*_full.vmf' -or $template -like '*_half.vmf') { 320 } elseif ($template -like '*_quarter.vmf') { 160 } else { [double]$dimensions[0].height / 2 }
        foreach ($side in @($base[0].Children | Where-Object Name -eq side)) {
            if ($null -eq $side.Child('vertices_plus') -or $null -ne $side.Child('dispinfo')) { throw "Infill base ground requires flat saved windings: $path" }
            foreach ($text in $side.Child('vertices_plus').GetAll('v')) {
                $point = [ZombieSim.Skybox.Vec3]::Parse($text)
                if ($point.Z -notin @(0, 32) -or $point.X -notin @(-$halfX, $halfX) -or $point.Y -notin @(-$halfY, $halfY)) { throw "Infill base ground footprint/height changed: $path. Preserve its canonical dimensions when adding artwork." }
                $corners["$($point.X),$($point.Y),$($point.Z)"] = $true
            }
        }
        if ($corners.Count -ne 8) { throw "Infill base ground must retain its full rectangular footprint: $path" }
    }
    $filledArea = 0
    foreach ($placement in $placements) { $filledArea += $(if ($null -ne $placement.PSObject.Properties['area']) { $placement.area } else { [double]$placement.width * [double]$placement.height }) }
    return [pscustomobject]@{
        schemaVersion = 1; groundBottom = 0; groundTop = 32; gridPitch = 320
        placements = @($placements); sourceFingerprints = $fingerprints
        requiredRectangles = $requiredRectangles
        filledArea = $filledArea
        blockedQuarterSlots = $blocked
        unmergedPartialGapCount = $unmergedGapCount
        partialGaps = @($partialGaps)
        unfilledRectangles = @($unfilled)
        groundCoverage = @($obstacles)
        status = 'rectangular_ground_only_fractional_and_nonstandard_boundaries_require_review'
        limits = @('Only recognized ground bases establish coverage. Protected/nonstandard nominal footprints are reservations, not claims of ground completeness.', 'No polygon fillers, decimal-sized patches, resizing or source overwrite. Structural/prop clearance remains an independent gate.')
    }
}

Export-ModuleMember -Function Get-ZMInfillObstacles, Get-ZMInfillGroundCoverage, Set-ZMInspectionTerrainInfill, Get-ZMInfillPatchName, Get-ZMInfillRectanglePieces, Get-ZMInfillShape, New-ZMInfillShapeVmf, New-ZMInfillRectangleVmf
