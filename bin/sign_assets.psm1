Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
if (-not ('ZombieSim.SignAssets.Builder' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Text;

namespace ZombieSim.SignAssets {
    public static class Builder {
        static readonly CultureInfo CI = CultureInfo.InvariantCulture;

        public static void DrawArtwork(string path, int width, int height, string background,
            string foreground, string accent, string title, string subtitle, string footer) {
            using (var bitmap = new Bitmap(width, height))
            using (var g = Graphics.FromImage(bitmap))
            using (var ink = new SolidBrush(ColorTranslator.FromHtml(foreground)))
            using (var stripe = new SolidBrush(ColorTranslator.FromHtml(accent)))
            using (var titleFont = new Font(FontFamily.GenericSansSerif, height * 0.145f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var subtitleFont = new Font(FontFamily.GenericSansSerif, height * 0.051f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var footerFont = new Font(FontFamily.GenericSansSerif, height * 0.034f, FontStyle.Regular, GraphicsUnit.Pixel))
            using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center }) {
                g.Clear(ColorTranslator.FromHtml(background));
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                g.FillRectangle(stripe, width * 0.04f, height * 0.07f, width * 0.92f, height * 0.035f);
                g.FillRectangle(stripe, width * 0.04f, height * 0.86f, width * 0.92f, height * 0.035f);
                g.DrawString(title, titleFont, ink, new RectangleF(width * 0.04f, height * 0.22f, width * 0.92f, height * 0.25f), format);
                g.DrawString(subtitle, subtitleFont, ink, new RectangleF(width * 0.04f, height * 0.49f, width * 0.92f, height * 0.15f), format);
                g.DrawString(footer, footerFont, ink, new RectangleF(width * 0.04f, height * 0.69f, width * 0.92f, height * 0.10f), format);
                bitmap.Save(path, ImageFormat.Png);
            }
        }

        public static void WriteTga(string imagePath, string outputPath, int width, int height) {
            WriteTga(imagePath, outputPath, width, height, false);
        }

        public static void WriteTga(string imagePath, string outputPath, int width, int height, bool allowTransparency) {
            using (var input = new Bitmap(imagePath)) {
                if (input.Width != width || input.Height != height)
                    throw new InvalidDataException("Artwork must be exactly " + width + "x" + height + "; it is not stretched automatically.");
                using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                    using (var graphics = Graphics.FromImage(bitmap)) graphics.DrawImageUnscaled(input, 0, 0);
                    var data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                    try {
                        using (var writer = new BinaryWriter(File.Create(outputPath))) {
                            writer.Write(new byte[] { 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
                            writer.Write((ushort)width); writer.Write((ushort)height);
                            writer.Write((byte)32); writer.Write((byte)0x28);
                            var row = new byte[width * 4];
                            for (int y = 0; y < height; y++) {
                                System.Runtime.InteropServices.Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                                for (int x = 0; x < width; x++)
                                    if (!allowTransparency && row[x * 4 + 3] != 255) throw new InvalidDataException("Billboard artwork must be opaque.");
                                writer.Write(row);
                            }
                        }
                    } finally { bitmap.UnlockBits(data); }
                }
            }
        }

        public static void ComposeArtwork(string outputPath, string foregroundPath, string backgroundPath, string fallbackPath, string background) {
            using (var bitmap = new Bitmap(1024, 512, PixelFormat.Format32bppArgb))
            using (var g = Graphics.FromImage(bitmap)) {
                g.Clear(ColorTranslator.FromHtml(background));
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceOver;
                if (!string.IsNullOrEmpty(backgroundPath)) {
                    using (var image = Image.FromFile(backgroundPath))
                    using (var attributes = new ImageAttributes()) {
                        double scale = Math.Max(1024.0 / image.Width, 512.0 / image.Height);
                        float w = (float)(image.Width * scale), h = (float)(image.Height * scale);
                        attributes.SetWrapMode(System.Drawing.Drawing2D.WrapMode.TileFlipXY);
                        g.DrawImage(image, Rectangle.Round(new RectangleF((1024-w)/2, (512-h)/2, w, h)),
                            0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attributes);
                    }
                }
                string front = string.IsNullOrEmpty(foregroundPath) && string.IsNullOrEmpty(backgroundPath) ? fallbackPath : foregroundPath;
                if (!string.IsNullOrEmpty(front)) {
                    using (var image = Image.FromFile(front)) {
                        double scale = Math.Min(960.0 / image.Width, 448.0 / image.Height);
                        if (front == fallbackPath) scale = 1;
                        float w = (float)(image.Width * scale), h = (float)(image.Height * scale);
                        g.DrawImage(image, (1024-w)/2, (512-h)/2, w, h);
                    }
                }
                bitmap.Save(outputPath, ImageFormat.Png);
            }
        }

        static void Vertex(StringBuilder text, double[] p, double[] n, double u, double v, double[] center = null) {
            if (center != null) {
                double length = Math.Sqrt(3);
                n = new double[]{Math.Sign(p[0] - center[0]) / length, Math.Sign(p[1] - center[1]) / length, Math.Sign(p[2] - center[2]) / length};
                u = 0; v = 0;
            }
            // Match the existing skybox builder's compensation for studiomdl's +90-degree SMD rotation.
            text.AppendFormat(CI, "0 {0} {1} {2} {3} {4} {5} {6} {7}\n",
                p[1], -p[0], p[2], n[1], -n[0], n[2], u, v);
        }

        static void Face(StringBuilder text, string material, double[] a, double[] b, double[] c, double[] d, double[] normal, double[] center = null) {
            if (center == null) {
                double[] ab=new double[]{b[0]-a[0],b[1]-a[1],b[2]-a[2]};
                double[] ac=new double[]{c[0]-a[0],c[1]-a[1],c[2]-a[2]};
                var n=new double[]{ac[1]*ab[2]-ac[2]*ab[1],ac[2]*ab[0]-ac[0]*ab[2],ac[0]*ab[1]-ac[1]*ab[0]};
                double length=Math.Sqrt(n[0]*n[0]+n[1]*n[1]+n[2]*n[2]);
                if (length < 1e-8) throw new InvalidDataException("Degenerate sign face.");
                normal=new double[]{n[0]/length,n[1]/length,n[2]/length};
            }
            double u = Math.Sqrt(Math.Pow(b[0]-a[0],2)+Math.Pow(b[1]-a[1],2)+Math.Pow(b[2]-a[2],2))/64;
            double v = Math.Sqrt(Math.Pow(d[0]-a[0],2)+Math.Pow(d[1]-a[1],2)+Math.Pow(d[2]-a[2],2))/64;
            text.AppendLine(material);
            Vertex(text, a, normal, 0, 0, center); Vertex(text, c, normal, u, v, center); Vertex(text, b, normal, u, 0, center);
            text.AppendLine(material);
            Vertex(text, a, normal, 0, 0, center); Vertex(text, d, normal, 0, v, center); Vertex(text, c, normal, u, v, center);
        }

        static void Box(StringBuilder text, string material, double x0, double y0, double z0, double x1, double y1, double z1, bool collision) {
            var center = collision ? new double[]{(x0+x1)/2, (y0+y1)/2, (z0+z1)/2} : null;
            Face(text, material, new[]{x0,y0,z0}, new[]{x0,y0,z1}, new[]{x1,y0,z1}, new[]{x1,y0,z0}, new double[]{0,-1,0}, center);
            Face(text, material, new[]{x1,y1,z0}, new[]{x1,y1,z1}, new[]{x0,y1,z1}, new[]{x0,y1,z0}, new double[]{0,1,0}, center);
            Face(text, material, new[]{x0,y1,z0}, new[]{x0,y1,z1}, new[]{x0,y0,z1}, new[]{x0,y0,z0}, new double[]{-1,0,0}, center);
            Face(text, material, new[]{x1,y0,z0}, new[]{x1,y0,z1}, new[]{x1,y1,z1}, new[]{x1,y1,z0}, new double[]{1,0,0}, center);
            Face(text, material, new[]{x0,y0,z1}, new[]{x0,y1,z1}, new[]{x1,y1,z1}, new[]{x1,y0,z1}, new double[]{0,0,1}, center);
            Face(text, material, new[]{x0,y1,z0}, new[]{x0,y0,z0}, new[]{x1,y0,z0}, new[]{x1,y1,z0}, new double[]{0,0,-1}, center);
        }

        public static string Mesh(bool collision) {
            return MeshVariant(collision, "freestanding");
        }

        static void Bezel(StringBuilder text, double x, double left, double bottom, double low, double high, double top) {
            double[] normal = new double[]{0,-1,0};
            // Outer lip, sloped reveal and inner gasket leave the full artwork rectangle unobstructed.
            double[] widths = new double[]{x, x-2, -left+1, -left};
            double[] bottoms = new double[]{bottom, bottom+2, low-1, low};
            double[] tops = new double[]{top, top-2, high+1, high};
            double[] depths = new double[]{-8.5, -11, -9, -8.4};
            for (int i=0; i<3; i++) {
                double a=widths[i], b=widths[i+1], z0=bottoms[i], z1=bottoms[i+1], t0=tops[i], t1=tops[i+1];
                double y0=depths[i], y1=depths[i+1];
                string material = i==2 ? "billboard_legs" : "billboard_rim";
                Face(text, material, new[]{-a,y0,z0}, new[]{-b,y1,z1}, new[]{b,y1,z1}, new[]{a,y0,z0}, normal);
                Face(text, material, new[]{a,y0,t0}, new[]{b,y1,t1}, new[]{-b,y1,t1}, new[]{-a,y0,t0}, normal);
                Face(text, material, new[]{-a,y0,t0}, new[]{-b,y1,t1}, new[]{-b,y1,z1}, new[]{-a,y0,z0}, normal);
                Face(text, material, new[]{a,y0,z0}, new[]{b,y1,z1}, new[]{b,y1,t1}, new[]{a,y0,t0}, normal);
            }
        }

        static void Bolt(StringBuilder text, double x, double y, double z) {
            double[] front = new double[]{0,-1,0};
            for (int i=0; i<6; i++) {
                double a=i*Math.PI/3, b=(i+1)*Math.PI/3;
                var p=new double[]{x+1.6*Math.Cos(a),y,z+1.6*Math.Sin(a)};
                var q=new double[]{x+1.6*Math.Cos(b),y,z+1.6*Math.Sin(b)};
                text.AppendLine("billboard_legs");
                Vertex(text,new double[]{x,y,z},front,0.5,0.5);
                Vertex(text,p,front,0,0); Vertex(text,q,front,1,0);
                var outward=new double[]{Math.Cos((a+b)/2),0,Math.Sin((a+b)/2)};
                Face(text,"billboard_legs",p,new[]{p[0],y+0.8,p[2]},new[]{q[0],y+0.8,q[2]},q,outward);
            }
        }

        public static string MeshVariant(bool collision, string variant) {
            if (variant != "freestanding" && variant != "panel" && variant != "illuminated" && variant != "wall" &&
                variant != "print" && variant != "poster")
                throw new ArgumentException("Unknown sign variant: " + variant);
            bool legs = variant == "freestanding" || variant == "illuminated";
            bool wall = variant == "wall";
            bool print = variant == "print", poster = variant == "poster";
            bool detailed = legs || variant == "panel";
            double x = wall ? 52 : 136, y = wall ? 4 : 8;
            double bottom = legs ? 152 : wall ? -28 : print ? -72 : poster ? -64 : 0;
            double top = legs ? 296 : wall ? 28 : print ? 72 : poster ? 64 : 144;
            double left = wall ? -48 : -128, right = -left;
            double low = bottom + (wall ? 4 : 8), high = top - (wall ? 4 : 8);
            var text = new StringBuilder("version 1\nnodes\n0 \"root\" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\ntriangles\n");
            if (poster && collision) throw new ArgumentException("A paper-thin poster deliberately has no collision mesh.");
            if (!poster) Box(text, "billboard_back", -x, print ? -2 : wall ? -y*2 : -y,
                bottom, x, print || wall ? 0 : detailed ? 20 : y, top, collision);
            if (legs) foreach (double post in new double[]{-96,96}) {
                if (collision) Box(text, "billboard_legs", post-8, -8, 0, post+8, 8, 152, true);
                else {
                    Box(text, "billboard_legs", post-8, -8, 0, post+8, -5, 152, false);
                    Box(text, "billboard_legs", post-2, -5, 0, post+2, 5, 152, false);
                    Box(text, "billboard_legs", post-8, 5, 0, post+8, 8, 152, false);
                    Box(text, "billboard_legs", post-10, -10, 144, post+10, 10, 152, false);
                }
                Box(text, "billboard_legs", post-14, -14, 0, post+14, 14, 5, collision);
                if (!collision) foreach (double offset in new double[]{-10,10}) Bolt(text,post+offset,-14.8,2.5);
            }
            if (variant == "illuminated") {
                Box(text, "billboard_legs", -3, -56, 292, 3, 0, 300, collision);
                Box(text, "billboard_legs", -24, -62, 300, 24, -50, 306, collision);
                if (!collision) {
                    Face(text, "billboard_lamp", new double[]{-21,-52,299.9}, new double[]{-21,-60,299.9},
                        new double[]{21,-60,299.9}, new double[]{21,-52,299.9}, new double[]{0,0,-1});
                }
            }
            if (!collision) {
                double faceY = print ? -2.3 : poster ? -0.1 : -8.3;
                if (detailed) {
                    Bezel(text,x,left,bottom,low,high,top);
                    foreach (double boltX in new double[]{-132,132})
                        foreach (double boltZ in new double[]{bottom+4,(bottom+top)/2,top-4}) Bolt(text,boltX,-11.8,boltZ);
                    foreach (double railZ in new double[]{bottom+12,top-12})
                        Box(text,"billboard_legs",-x+8,20,railZ,x-8,24,railZ+4,false);
                    foreach (double railX in new double[]{-96,0,96})
                        Box(text,"billboard_legs",railX-2,20,bottom+16,railX+2,24,top-16,false);
                } else if (!poster) {
                    Box(text, "billboard_rim", -x, faceY, bottom, x, faceY+0.3, low, false);
                    Box(text, "billboard_rim", -x, faceY, high, x, faceY+0.3, top, false);
                    Box(text, "billboard_rim", -x, faceY, low, left, faceY+0.3, high, false);
                    Box(text, "billboard_rim", right, faceY, low, x, faceY+0.3, high, false);
                }
                if (poster) { low=bottom; high=top; }
                var normal = new double[]{0,-1,0};
                double artworkY = poster ? faceY : faceY+0.2;
                var a = new double[]{left,artworkY,low}; var b = new double[]{right,artworkY,low};
                var c = new double[]{right,artworkY,high}; var d = new double[]{left,artworkY,high};
                string panel = variant == "illuminated" ? "alert_billboard_lit" : "alert_billboard";
                text.AppendLine(panel);
                Vertex(text, a, normal, 0, 0); Vertex(text, b, normal, 1, 0); Vertex(text, c, normal, 1, 1);
                text.AppendLine(panel);
                Vertex(text, a, normal, 0, 0); Vertex(text, c, normal, 1, 1); Vertex(text, d, normal, 0, 1);
            }
            text.AppendLine("end");
            return text.ToString();
        }
    }
}
'@
}

function Get-SignArtworkDefinition {
    param([Parameter(Mandatory)][string]$Path)
    $definition = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in 'width', 'height', 'background', 'foreground', 'accent', 'title', 'subtitle', 'footer') {
        if ($null -eq $definition.PSObject.Properties[$name]) { throw "Missing artwork field: $name" }
    }
    if ($definition.width -ne 1024 -or $definition.height -ne 512) { throw 'The prototype uses a 1024x512 artwork canvas.' }
    foreach ($name in 'background', 'foreground', 'accent') {
        if ([string]$definition.$name -notmatch '^#[0-9A-Fa-f]{6}$') { throw "Invalid artwork colour: $name" }
    }
    foreach ($name in 'title', 'subtitle', 'footer') {
        if ([string]::IsNullOrWhiteSpace([string]$definition.$name)) { throw "Empty artwork text: $name" }
    }
    foreach ($name in 'imagePath', 'backgroundImagePath') {
        if ($null -ne $definition.PSObject.Properties[$name] -and $definition.$name -isnot [string]) {
            throw "$name must be a string (empty to disable the layer)."
        }
    }
    if ($null -ne $definition.PSObject.Properties['selfLit'] -and $definition.selfLit -isnot [bool]) {
        throw 'selfLit must be a JSON boolean.'
    }
    if ($null -ne $definition.PSObject.Properties['selfIllumBrightness'] -and
        ($definition.selfIllumBrightness -isnot [ValueType] -or $definition.selfIllumBrightness -is [bool] -or [double]$definition.selfIllumBrightness -lt 0 -or
        [double]$definition.selfIllumBrightness -gt 1)) { throw 'selfIllumBrightness must be between 0 and 1.' }
    if ($null -eq $definition.PSObject.Properties['materials']) { throw 'Missing materials: legs, rim and back must specify their mounted textures.' }
    foreach ($component in 'legs', 'rim', 'back') {
        if ($null -eq $definition.materials.PSObject.Properties[$component]) { throw "Missing material component: $component" }
        $material = $definition.materials.$component
        foreach ($key in 'baseTexture', 'normalMap') {
            if ($null -eq $material.PSObject.Properties[$key] -or $material.$key -isnot [string]) { throw "Missing or invalid $component.$key" }
            $value = [string]$material.$key
            if (($key -eq 'baseTexture' -or $value) -and $value -notmatch '^[a-zA-Z0-9_/-]+$') { throw "Invalid mounted texture path: $component.$key" }
        }
    }
    return $definition
}

function Get-SignPanelMaterial {
    param([bool]$SelfLit, [double]$Brightness)
    if ([double]::IsNaN($Brightness) -or $Brightness -lt 0 -or $Brightness -gt 1) { throw 'Invalid self-illumination brightness.' }
    $light = if ($SelfLit) { 1 } else { 0 }
    $value = $Brightness.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    return @"
"VertexLitGeneric"
{
    "`$basetexture" "models/zombiesim/signs/alert_billboard"
    "`$surfaceprop" "metal"
    "`$selfillum" "$light"
    "`$selfillumtint" "[$value $value $value]"
}
"@
}

function Invoke-SignCompiler {
    param([string]$Executable, [string]$Arguments, [string]$LogPath)
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $Executable
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.WorkingDirectory = Split-Path -Parent $Executable
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Sign compiler timed out: $Executable"
        }
        [System.IO.File]::WriteAllText($LogPath, $stdout.Result + $stderr.Result)
        if ($process.ExitCode -ne 0) { throw "Sign compiler exited $($process.ExitCode); see $LogPath" }
    } finally { $process.Dispose() }
}

Export-ModuleMember -Function Get-SignArtworkDefinition, Get-SignPanelMaterial, Invoke-SignCompiler
