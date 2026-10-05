using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class ZombieSimFabricRendererV3
{
    public static void DrawBack(Graphics graphics, Bitmap source, double[][] triangles,
        double originX, double originY, double topZ, double scaleX, double scaleY, bool wrap)
    {
        const int size = 1024;
        byte[] output = new byte[size * size * 4];
        byte[] input = new byte[source.Width * source.Height * 4];
        BitmapData inputData = source.LockBits(new Rectangle(0, 0, source.Width, source.Height),
            ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            for (int y = 0; y < source.Height; y++)
                Marshal.Copy(IntPtr.Add(inputData.Scan0, y * inputData.Stride), input, y * source.Width * 4, source.Width * 4);
        }
        finally { source.UnlockBits(inputData); }
        foreach (double[] t in triangles)
        {
            if (t.Length != 15) throw new ArgumentException("Back projection requires three UV/XYZ vertices.");
            double determinant = (t[6] - t[11]) * (t[0] - t[10]) + (t[10] - t[5]) * (t[1] - t[11]);
            if (Math.Abs(determinant) < 0.000001) continue;
            int minX = Math.Max(0, (int)Math.Floor(Math.Min(t[0], Math.Min(t[5], t[10]))) - 2);
            int maxX = Math.Min(size - 1, (int)Math.Ceiling(Math.Max(t[0], Math.Max(t[5], t[10]))) + 2);
            int minY = Math.Max(0, (int)Math.Floor(Math.Min(t[1], Math.Min(t[6], t[11]))) - 2);
            int maxY = Math.Min(size - 1, (int)Math.Ceiling(Math.Max(t[1], Math.Max(t[6], t[11]))) + 2);
            double da = Math.Sqrt(Math.Pow(t[6] - t[11], 2) + Math.Pow(t[10] - t[5], 2)) / Math.Abs(determinant);
            double db = Math.Sqrt(Math.Pow(t[11] - t[1], 2) + Math.Pow(t[0] - t[10], 2)) / Math.Abs(determinant);
            double dc = Math.Sqrt(Math.Pow(t[1] - t[6], 2) + Math.Pow(t[5] - t[0], 2)) / Math.Abs(determinant);
            for (int y = minY; y <= maxY; y++)
            {
                for (int x = minX; x <= maxX; x++)
                {
                    double a = ((t[6] - t[11]) * (x + 0.5 - t[10]) + (t[10] - t[5]) * (y + 0.5 - t[11])) / determinant;
                    double b = ((t[11] - t[1]) * (x + 0.5 - t[10]) + (t[0] - t[10]) * (y + 0.5 - t[11])) / determinant;
                    double c = 1 - a - b;
                    // Bleed two texture pixels beyond chart edges to prevent filtering showing a bare seam.
                    if (a < -2 * da || b < -2 * db || c < -2 * dc) continue;
                    if ((a < 0 || b < 0 || c < 0) &&
                        Math.Min(SegmentDistanceSquared(x + 0.5, y + 0.5, t[0], t[1], t[5], t[6]),
                            Math.Min(SegmentDistanceSquared(x + 0.5, y + 0.5, t[5], t[6], t[10], t[11]),
                                SegmentDistanceSquared(x + 0.5, y + 0.5, t[10], t[11], t[0], t[1]))) > 4) continue;
                    double worldX = a * t[2] + b * t[7] + c * t[12];
                    double worldZ = a * t[4] + b * t[9] + c * t[14];
                    double sx = originX - worldX * scaleX;
                    double sy = originY + (topZ - worldZ) * scaleY;
                    if (wrap)
                    {
                        sx = (sx % source.Width + source.Width) % source.Width;
                        sy = (sy % source.Height + source.Height) % source.Height;
                    }
                    else if (sx < 0 || sy < 0 || sx >= source.Width || sy >= source.Height) continue;
                    int ix = (int)Math.Floor(sx), iy = (int)Math.Floor(sy);
                    double fx = sx - ix, fy = sy - iy;
                    int nx = wrap ? (ix + 1) % source.Width : Math.Min(ix + 1, source.Width - 1);
                    int ny = wrap ? (iy + 1) % source.Height : Math.Min(iy + 1, source.Height - 1);
                    int offset = (y * size + x) * 4;
                    int p00 = (iy * source.Width + ix) * 4;
                    int p10 = (iy * source.Width + nx) * 4;
                    int p01 = (ny * source.Width + ix) * 4;
                    int p11 = (ny * source.Width + nx) * 4;
                    double w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
                    double alpha = input[p00 + 3] * w00 + input[p10 + 3] * w10
                        + input[p01 + 3] * w01 + input[p11 + 3] * w11;
                    output[offset + 3] = (byte)Math.Round(alpha);
                    if (alpha < 0.000001) continue;
                    for (int channel = 0; channel < 3; channel++)
                    {
                        output[offset + channel] = (byte)Math.Round((input[p00 + channel] * input[p00 + 3] * w00
                            + input[p10 + channel] * input[p10 + 3] * w10 + input[p01 + channel] * input[p01 + 3] * w01
                            + input[p11 + channel] * input[p11 + 3] * w11) / alpha);
                    }
                }
            }
        }
        using (Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        {
            BitmapData data = bitmap.LockBits(new Rectangle(0, 0, size, size),
                ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try
            {
                for (int y = 0; y < size; y++)
                    Marshal.Copy(output, y * size * 4, IntPtr.Add(data.Scan0, y * data.Stride), size * 4);
            }
            finally { bitmap.UnlockBits(data); }
            graphics.DrawImageUnscaled(bitmap, 0, 0);
        }
    }

    private static double SegmentDistanceSquared(double x, double y, double ax, double ay, double bx, double by)
    {
        double dx = bx - ax, dy = by - ay;
        double length = dx * dx + dy * dy;
        double along = length == 0 ? 0 : Math.Max(0, Math.Min(1, ((x - ax) * dx + (y - ay) * dy) / length));
        double ex = x - ax - along * dx, ey = y - ay - along * dy;
        return ex * ex + ey * ey;
    }

    public static void DrawDye(Graphics graphics, Color basis, Color[] palette,
        double centerX, double centerY, double scale, double strength, int seed, string style)
    {
        const int size = 1024;
        byte[] pixels = new byte[size * size * 4];
        double phase = seed * Math.PI / 180.0;
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                double dx = (x + 0.5 - centerX) / scale;
                double dy = (y + 0.5 - centerY) / scale;
                double radius = Math.Sqrt(dx * dx + dy * dy);
                double angle = Math.Atan2(dy, dx);
                double turbulence = 0.18 * Math.Sin(dx * 3.1 + phase) * Math.Cos(dy * 2.7 - phase)
                    + 0.08 * Math.Sin(dx * 8.3 + dy * 5.9 + phase);
                double wave;
                if (style == "rings")
                    wave = radius * Math.PI * 2 + turbulence * 2 + phase;
                else if (style == "cloud")
                    wave = Math.Sin(dx * 1.8 + phase) * 2 + Math.Cos(dy * 2.1 - phase) * 2
                        + turbulence * 3;
                else if (style == "marble")
                    wave = dx * 3 + Math.Sin(dy * 2.5 + phase) * 2.2 + turbulence * 4;
                else
                    wave = radius * Math.PI * 2 + angle * 2 + turbulence + phase;
                double position = (0.5 + 0.5 * Math.Sin(wave)) * (palette.Length - 1);
                int index = Math.Min((int)Math.Floor(position), palette.Length - 2);
                double blend = position - index;
                // Smooth dye absorption and fine original textile grain, evaluated at every texel.
                blend = blend * blend * (3 - 2 * blend);
                double fiber = strength * (0.65 * Math.Sin(x * 2.6) * Math.Cos(y * 2.3)
                    + 0.35 * Math.Sin(x * 0.71 + y * 1.13 + phase));
                int offset = (y * size + x) * 4;
                pixels[offset] = Channel(basis.B, palette[index].B, palette[index + 1].B, blend, strength, fiber);
                pixels[offset + 1] = Channel(basis.G, palette[index].G, palette[index + 1].G, blend, strength, fiber);
                pixels[offset + 2] = Channel(basis.R, palette[index].R, palette[index + 1].R, blend, strength, fiber);
                pixels[offset + 3] = 255;
            }
        }
        using (Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        {
            BitmapData data = bitmap.LockBits(new Rectangle(0, 0, size, size),
                ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try
            {
                for (int y = 0; y < size; y++)
                    Marshal.Copy(pixels, y * size * 4, IntPtr.Add(data.Scan0, y * data.Stride), size * 4);
            }
            finally { bitmap.UnlockBits(data); }
            graphics.DrawImageUnscaled(bitmap, 0, 0);
        }
    }

    private static byte Channel(byte basis, byte first, byte second, double blend, double strength, double fiber)
    {
        double target = first * (1 - blend) + second * blend;
        return (byte)Math.Max(0, Math.Min(255, Math.Round(basis * (1 - strength) + target * strength + fiber)));
    }
}
