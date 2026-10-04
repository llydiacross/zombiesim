Set-StrictMode -Version Latest

# Converts generated recipe VMFs (and the tiletemplate VMFs they instance) into scaled SMD meshes for the 3D skybox.
# Geometry comes from Hammer++ vertices_plus windings and dispinfo grids; texture coordinates use the source
# uaxis/vaxis so scaled models keep world texel density once the skybox camera magnifies them.
if (-not ('ZombieSim.Skybox.CellModelBuilder' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace ZombieSim.Skybox {
    public sealed class VmfNode {
        public string Name;
        public readonly List<KeyValuePair<string, string>> Keys = new List<KeyValuePair<string, string>>();
        public readonly List<VmfNode> Children = new List<VmfNode>();
        public string Get(string key) {
            foreach (var kv in Keys) if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase)) return kv.Value;
            return null;
        }
        public IEnumerable<string> GetAll(string key) {
            foreach (var kv in Keys) if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase)) yield return kv.Value;
        }
        public VmfNode Child(string name) {
            foreach (var c in Children) if (string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase)) return c;
            return null;
        }
    }

    public static class KeyValuesParser {
        public static VmfNode Parse(string text) {
            var root = new VmfNode { Name = "root" };
            var stack = new Stack<VmfNode>();
            stack.Push(root);
            string pending = null;
            int i = 0, n = text.Length;
            while (i < n) {
                char c = text[i];
                if (char.IsWhiteSpace(c)) { i++; continue; }
                if (c == '/' && i + 1 < n && text[i + 1] == '/') { while (i < n && text[i] != '\n') i++; continue; }
                if (c == '{') {
                    var node = new VmfNode { Name = pending ?? "" };
                    stack.Peek().Children.Add(node);
                    stack.Push(node);
                    pending = null; i++; continue;
                }
                if (c == '}') { if (stack.Count > 1) stack.Pop(); pending = null; i++; continue; }
                string token;
                if (c == '"') {
                    int j = text.IndexOf('"', i + 1);
                    if (j < 0) j = n;
                    token = text.Substring(i + 1, j - i - 1);
                    i = j + 1;
                } else {
                    int j = i;
                    while (j < n && !char.IsWhiteSpace(text[j]) && text[j] != '{' && text[j] != '}' && text[j] != '"') j++;
                    token = text.Substring(i, j - i);
                    i = j;
                }
                if (pending == null) pending = token;
                else { stack.Peek().Keys.Add(new KeyValuePair<string, string>(pending, token)); pending = null; }
            }
            return root;
        }
    }

    public struct Vec3 {
        public double X, Y, Z;
        public Vec3(double x, double y, double z) { X = x; Y = y; Z = z; }
        public static Vec3 operator +(Vec3 a, Vec3 b) { return new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static Vec3 operator -(Vec3 a, Vec3 b) { return new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static Vec3 operator *(Vec3 a, double s) { return new Vec3(a.X * s, a.Y * s, a.Z * s); }
        public double Dot(Vec3 b) { return X * b.X + Y * b.Y + Z * b.Z; }
        public Vec3 Cross(Vec3 b) { return new Vec3(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X); }
        public double Length { get { return Math.Sqrt(Dot(this)); } }
        public Vec3 Normalized() { double l = Length; return l > 1e-9 ? this * (1.0 / l) : new Vec3(0, 0, 1); }
        public static Vec3 Parse(string text) {
            var parts = text.Trim().Trim('[', ']', '(', ')').Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            return new Vec3(D(parts[0]), D(parts[1]), D(parts[2]));
        }
        internal static double D(string s) { return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture); }
    }

    public sealed class Triangle {
        public string Material;
        public Vec3[] P = new Vec3[3];
        public Vec3[] N = new Vec3[3];
        public double[] S = new double[3];
        public double[] T = new double[3];
    }

    public sealed class TextureAxis {
        public Vec3 Axis; public double Offset; public double Scale;
        public static TextureAxis Parse(string text) {
            // "[x y z offset] scale"
            int close = text.IndexOf(']');
            var inner = text.Substring(text.IndexOf('[') + 1, close - text.IndexOf('[') - 1).Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            double scale = Vec3.D(text.Substring(close + 1).Trim());
            return new TextureAxis { Axis = new Vec3(Vec3.D(inner[0]), Vec3.D(inner[1]), Vec3.D(inner[2])), Offset = Vec3.D(inner[3]), Scale = Math.Abs(scale) < 1e-9 ? 0.25 : scale };
        }
        public double Map(Vec3 p) { return p.Dot(Axis) / Scale + Offset; }
    }

    public sealed class TileProp { public string Model; public Vec3 Origin; public Vec3 Angles; public int Skin; }

    // Horizontal, upward-facing brush face (axis-aligned bounds), used to find road lanes and rooftops.
    public sealed class UpFace { public string Material; public double MinX, MinY, MaxX, MaxY, Z; }

    public sealed class TileMesh {
        public readonly List<Triangle> Triangles = new List<Triangle>();
        public readonly HashSet<string> Materials = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public readonly List<TileProp> Props = new List<TileProp>();
        public readonly List<UpFace> UpFaces = new List<UpFace>();
        public int SkippedSolids;
        public int MissingWindings;
    }

    public static class TileMeshBuilder {
        static readonly HashSet<string> BrushEntities = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "func_detail", "func_brush", "func_illusionary", "func_wall" };

        public static TileMesh Build(string vmfText, double minBrushExtent) {
            var root = KeyValuesParser.Parse(vmfText);
            var mesh = new TileMesh();
            foreach (var top in root.Children) {
                if (string.Equals(top.Name, "world", StringComparison.OrdinalIgnoreCase)) {
                    CollectSolids(top, mesh, minBrushExtent);
                } else if (string.Equals(top.Name, "entity", StringComparison.OrdinalIgnoreCase)) {
                    string cls = top.Get("classname") ?? "";
                    if (BrushEntities.Contains(cls)) CollectSolids(top, mesh, minBrushExtent);
                    string model = top.Get("model");
                    if (cls.StartsWith("prop_", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(model) && model.EndsWith(".mdl", StringComparison.OrdinalIgnoreCase)) {
                        int skin; int.TryParse(top.Get("skin") ?? "0", NumberStyles.Integer, CultureInfo.InvariantCulture, out skin);
                        mesh.Props.Add(new TileProp {
                            Model = model.Replace('\\', '/').ToLowerInvariant(),
                            Origin = Vec3.Parse(top.Get("origin") ?? "0 0 0"),
                            Angles = Vec3.Parse(top.Get("angles") ?? "0 0 0"),
                            Skin = skin
                        });
                    }
                }
            }
            return mesh;
        }

        static void CollectSolids(VmfNode owner, TileMesh mesh, double minBrushExtent) {
            foreach (var child in owner.Children) {
                if (string.Equals(child.Name, "solid", StringComparison.OrdinalIgnoreCase)) AddSolid(child, mesh, minBrushExtent);
                else if (string.Equals(child.Name, "hidden", StringComparison.OrdinalIgnoreCase)) CollectSolids(child, mesh, minBrushExtent);
            }
        }

        sealed class Side { public string Material; public List<Vec3> Points = new List<Vec3>(); public TextureAxis U, V; public VmfNode Disp; }

        static void AddSolid(VmfNode solid, TileMesh mesh, double minBrushExtent) {
            var sides = new List<Side>();
            foreach (var s in solid.Children) {
                if (!string.Equals(s.Name, "side", StringComparison.OrdinalIgnoreCase)) continue;
                var side = new Side { Material = (s.Get("material") ?? "").ToUpperInvariant() };
                var vp = s.Child("vertices_plus");
                if (vp == null) { mesh.MissingWindings++; return; }
                foreach (var v in vp.GetAll("v")) side.Points.Add(Vec3.Parse(v));
                string ua = s.Get("uaxis"), va = s.Get("vaxis");
                if (ua == null || va == null || side.Points.Count < 3) continue;
                side.U = TextureAxis.Parse(ua); side.V = TextureAxis.Parse(va);
                side.Disp = s.Child("dispinfo");
                sides.Add(side);
            }
            if (sides.Count == 0) return;
            var min = new Vec3(double.MaxValue, double.MaxValue, double.MaxValue);
            var max = new Vec3(double.MinValue, double.MinValue, double.MinValue);
            var centroid = new Vec3(0, 0, 0); int count = 0;
            bool hasDisp = false;
            foreach (var side in sides) {
                if (side.Disp != null) hasDisp = true;
                foreach (var p in side.Points) {
                    min = new Vec3(Math.Min(min.X, p.X), Math.Min(min.Y, p.Y), Math.Min(min.Z, p.Z));
                    max = new Vec3(Math.Max(max.X, p.X), Math.Max(max.Y, p.Y), Math.Max(max.Z, p.Z));
                    centroid = centroid + p; count++;
                }
            }
            centroid = centroid * (1.0 / count);
            var extent = max - min;
            if (!hasDisp && Math.Max(extent.X, Math.Max(extent.Y, extent.Z)) < minBrushExtent) { mesh.SkippedSolids++; return; }
            foreach (var side in sides) {
                if (hasDisp && side.Disp == null) continue;
                var normal = Newell(side.Points);
                var center = Average(side.Points);
                if (normal.Dot(center - centroid) < 0) normal = normal * -1;
                if (side.Disp == null && normal.Z < -0.99 && center.Z <= min.Z + 8 && min.Z <= 8) continue;
                if (side.Disp == null && normal.Z > 0.99) {
                    var face = new UpFace { Material = side.Material, MinX = double.MaxValue, MinY = double.MaxValue, MaxX = double.MinValue, MaxY = double.MinValue, Z = center.Z };
                    foreach (var p in side.Points) {
                        face.MinX = Math.Min(face.MinX, p.X); face.MaxX = Math.Max(face.MaxX, p.X);
                        face.MinY = Math.Min(face.MinY, p.Y); face.MaxY = Math.Max(face.MaxY, p.Y);
                    }
                    mesh.UpFaces.Add(face);
                }
                mesh.Materials.Add(side.Material);
                if (side.Disp != null) AddDisplacement(side, normal, mesh);
                else AddPolygon(side, normal, mesh);
            }
        }

        static Vec3 Newell(List<Vec3> pts) {
            var n = new Vec3(0, 0, 0);
            for (int i = 0; i < pts.Count; i++) {
                var a = pts[i]; var b = pts[(i + 1) % pts.Count];
                n = n + new Vec3((a.Y - b.Y) * (a.Z + b.Z), (a.Z - b.Z) * (a.X + b.X), (a.X - b.X) * (a.Y + b.Y));
            }
            return n.Normalized();
        }

        static Vec3 Average(List<Vec3> pts) {
            var c = new Vec3(0, 0, 0);
            foreach (var p in pts) c = c + p;
            return c * (1.0 / pts.Count);
        }

        static void Emit(TileMesh mesh, string material, Vec3 a, Vec3 b, Vec3 c, Vec3 na, Vec3 nb, Vec3 nc, Vec3 ta, Vec3 tb, Vec3 tc, Side side, Vec3 facing) {
            // Front faces are counter-clockwise around the outward normal, matching the SMD convention.
            var geometric = (b - a).Cross(c - a);
            if (geometric.Length < 1e-6) return;
            if (geometric.Dot(facing) < 0) {
                var tp = b; b = c; c = tp; var tn = nb; nb = nc; nc = tn; var tt = tb; tb = tc; tc = tt;
            }
            var tri = new Triangle { Material = material };
            tri.P[0] = a; tri.P[1] = b; tri.P[2] = c;
            tri.N[0] = na; tri.N[1] = nb; tri.N[2] = nc;
            tri.S[0] = side.U.Map(ta); tri.S[1] = side.U.Map(tb); tri.S[2] = side.U.Map(tc);
            tri.T[0] = side.V.Map(ta); tri.T[1] = side.V.Map(tb); tri.T[2] = side.V.Map(tc);
            mesh.Triangles.Add(tri);
        }

        static void AddPolygon(Side side, Vec3 normal, TileMesh mesh) {
            var p = side.Points;
            for (int i = 1; i + 1 < p.Count; i++)
                Emit(mesh, side.Material, p[0], p[i], p[i + 1], normal, normal, normal, p[0], p[i], p[i + 1], side, normal);
        }

        static double[] Row(VmfNode block, int row) {
            if (block == null) return null;
            var text = block.Get("row" + row);
            if (text == null) return null;
            var parts = text.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            var values = new double[parts.Length];
            for (int i = 0; i < parts.Length; i++) values[i] = Vec3.D(parts[i]);
            return values;
        }

        static void AddDisplacement(Side side, Vec3 faceNormal, TileMesh mesh) {
            if (side.Points.Count != 4) { AddPolygon(side, faceNormal, mesh); return; }
            var disp = side.Disp;
            int power = (int)Vec3.D(disp.Get("power") ?? "3");
            int size = (1 << power) + 1;
            var start = Vec3.Parse(disp.Get("startposition") ?? "[0 0 0]");
            double elevation = Vec3.D(disp.Get("elevation") ?? "0");
            int startIndex = 0; double best = double.MaxValue;
            for (int i = 0; i < 4; i++) {
                double d = (side.Points[i] - start).Length;
                if (d < best) { best = d; startIndex = i; }
            }
            var c = new Vec3[4];
            for (int i = 0; i < 4; i++) c[i] = side.Points[(startIndex + i) % 4];
            var normals = disp.Child("normals"); var distances = disp.Child("distances"); var offsets = disp.Child("offsets");
            var basePos = new Vec3[size, size];
            var pos = new Vec3[size, size];
            for (int i = 0; i < size; i++) {
                double ri = (double)i / (size - 1);
                var e0 = c[0] + (c[1] - c[0]) * ri;
                var e1 = c[3] + (c[2] - c[3]) * ri;
                var nRow = Row(normals, i); var dRow = Row(distances, i); var oRow = Row(offsets, i);
                for (int j = 0; j < size; j++) {
                    double rj = (double)j / (size - 1);
                    var b = e0 + (e1 - e0) * rj;
                    var p = b + faceNormal * elevation;
                    if (nRow != null && dRow != null && nRow.Length >= j * 3 + 3 && dRow.Length > j)
                        p = p + new Vec3(nRow[j * 3], nRow[j * 3 + 1], nRow[j * 3 + 2]) * dRow[j];
                    if (oRow != null && oRow.Length >= j * 3 + 3)
                        p = p + new Vec3(oRow[j * 3], oRow[j * 3 + 1], oRow[j * 3 + 2]);
                    basePos[i, j] = b; pos[i, j] = p;
                }
            }
            var vn = new Vec3[size, size];
            for (int i = 0; i + 1 < size; i++) for (int j = 0; j + 1 < size; j++) {
                var n1 = Oriented((pos[i + 1, j] - pos[i, j]).Cross(pos[i + 1, j + 1] - pos[i, j]), faceNormal);
                var n2 = Oriented((pos[i + 1, j + 1] - pos[i, j]).Cross(pos[i, j + 1] - pos[i, j]), faceNormal);
                vn[i, j] = vn[i, j] + n1 + n2; vn[i + 1, j] = vn[i + 1, j] + n1; vn[i + 1, j + 1] = vn[i + 1, j + 1] + n1 + n2; vn[i, j + 1] = vn[i, j + 1] + n2;
            }
            for (int i = 0; i < size; i++) for (int j = 0; j < size; j++) vn[i, j] = vn[i, j].Normalized();
            for (int i = 0; i + 1 < size; i++) for (int j = 0; j + 1 < size; j++) {
                Emit(mesh, side.Material, pos[i, j], pos[i + 1, j], pos[i + 1, j + 1], vn[i, j], vn[i + 1, j], vn[i + 1, j + 1], basePos[i, j], basePos[i + 1, j], basePos[i + 1, j + 1], side, faceNormal);
                Emit(mesh, side.Material, pos[i, j], pos[i + 1, j + 1], pos[i, j + 1], vn[i, j], vn[i + 1, j + 1], vn[i, j + 1], basePos[i, j], basePos[i + 1, j + 1], basePos[i, j + 1], side, faceNormal);
            }
        }

        static Vec3 Oriented(Vec3 n, Vec3 facing) { return n.Dot(facing) < 0 ? n * -1 : n; }
    }

    public sealed class InstancePlacement { public string File; public Vec3 Origin; public Vec3 Angles; }

    public sealed class MaterialInfo { public string ModelMaterial; public int Width; public int Height; }

    public sealed class CellModelPart { public string Smd; public int Triangles; public int Vertices; public Vec3 Min; public Vec3 Max; }

    public sealed class CellModelBuilder {
        readonly Dictionary<string, TileMesh> cache = new Dictionary<string, TileMesh>(StringComparer.OrdinalIgnoreCase);
        readonly double minBrushExtent;
        public CellModelBuilder(double minBrushExtent) { this.minBrushExtent = minBrushExtent; }

        public static List<InstancePlacement> ReadInstances(string recipePath) {
            var root = KeyValuesParser.Parse(File.ReadAllText(recipePath));
            var result = new List<InstancePlacement>();
            string directory = Path.GetDirectoryName(recipePath);
            foreach (var e in root.Children) {
                if (!string.Equals(e.Name, "entity", StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.Equals(e.Get("classname"), "func_instance", StringComparison.OrdinalIgnoreCase)) continue;
                var file = e.Get("file");
                if (string.IsNullOrEmpty(file)) continue;
                result.Add(new InstancePlacement {
                    File = Path.GetFullPath(Path.Combine(directory, file.Replace('/', Path.DirectorySeparatorChar))),
                    Origin = Vec3.Parse(e.Get("origin") ?? "0 0 0"),
                    Angles = Vec3.Parse(e.Get("angles") ?? "0 0 0")
                });
            }
            return result;
        }

        public TileMesh GetTile(string path) {
            TileMesh mesh;
            if (!cache.TryGetValue(path, out mesh)) {
                mesh = TileMeshBuilder.Build(File.ReadAllText(path), minBrushExtent);
                cache[path] = mesh;
            }
            return mesh;
        }

        public List<string> CollectMaterials(IEnumerable<string> recipePaths) {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var recipe in recipePaths)
                foreach (var placement in ReadInstances(recipe))
                    if (File.Exists(placement.File)) set.UnionWith(GetTile(placement.File).Materials);
            var list = new List<string>(set);
            list.Sort(StringComparer.OrdinalIgnoreCase);
            return list;
        }

        // Source AngleMatrix (pitch, yaw, roll) applied to local instance coordinates.
        static Vec3 Rotate(Vec3 v, Vec3 angles) {
            double p = angles.X * Math.PI / 180, y = angles.Y * Math.PI / 180, r = angles.Z * Math.PI / 180;
            double sp = Math.Sin(p), cp = Math.Cos(p), sy = Math.Sin(y), cy = Math.Cos(y), sr = Math.Sin(r), cr = Math.Cos(r);
            double m00 = cp * cy, m10 = cp * sy, m20 = -sp;
            double m01 = sr * sp * cy - cr * sy, m11 = sr * sp * sy + cr * cy, m21 = sr * cp;
            double m02 = cr * sp * cy + sr * sy, m12 = cr * sp * sy - sr * cy, m22 = cr * cp;
            return new Vec3(m00 * v.X + m01 * v.Y + m02 * v.Z, m10 * v.X + m11 * v.Y + m12 * v.Z, m20 * v.X + m21 * v.Y + m22 * v.Z);
        }

        static int CountNew(HashSet<string> existing, HashSet<string> added) {
            int count = 0;
            foreach (var m in added) if (!existing.Contains(m)) count++;
            return count;
        }

        static string F(double v) { return v.ToString("0.######", CultureInfo.InvariantCulture); }

        public List<CellModelPart> BuildParts(string recipePath, double scale, Dictionary<string, MaterialInfo> materials, int maxPartVertices, int maxPartMaterials) {
            var parts = new List<CellModelPart>();
            StringBuilder sb = null; HashSet<string> vertexKeys = null; HashSet<string> partMaterials = null; CellModelPart part = null;
            foreach (var placement in ReadInstances(recipePath)) {
                if (!File.Exists(placement.File)) continue;
                var mesh = GetTile(placement.File);
                var lines = new List<string>();
                var keys = new HashSet<string>();
                var tileMaterials = new HashSet<string>();
                foreach (var tri in mesh.Triangles) {
                    MaterialInfo info;
                    if (!materials.TryGetValue(tri.Material, out info) || info == null) continue;
                    lines.Add(info.ModelMaterial);
                    tileMaterials.Add(info.ModelMaterial);
                    for (int k = 0; k < 3; k++) {
                        var world = (Rotate(tri.P[k], placement.Angles) + placement.Origin) * scale;
                        var normal = Rotate(tri.N[k], placement.Angles).Normalized();
                        double u = tri.S[k] / info.Width;
                        double v = 1.0 - tri.T[k] / info.Height;
                        // studiomdl turns SMD (x, y) into model (-y, x); pre-rotate so the compiled model keeps map axes.
                        string row = "0 " + F(world.Y) + " " + F(-world.X) + " " + F(world.Z) + " " + F(normal.Y) + " " + F(-normal.X) + " " + F(normal.Z) + " " + F(u) + " " + F(v);
                        lines.Add(row);
                        keys.Add(info.ModelMaterial + "|" + row);
                    }
                }
                if (lines.Count == 0) continue;
                bool overVertices = part != null && vertexKeys.Count + keys.Count > maxPartVertices;
                bool overMaterials = part != null && partMaterials.Count + CountNew(partMaterials, tileMaterials) > maxPartMaterials;
                if (part == null || ((overVertices || overMaterials) && part.Triangles > 0)) {
                    if (part != null) { sb.AppendLine("end"); part.Smd = sb.ToString(); part.Vertices = vertexKeys.Count; parts.Add(part); }
                    part = new CellModelPart { Min = new Vec3(double.MaxValue, double.MaxValue, double.MaxValue), Max = new Vec3(double.MinValue, double.MinValue, double.MinValue) };
                    vertexKeys = new HashSet<string>();
                    partMaterials = new HashSet<string>();
                    sb = new StringBuilder();
                    sb.AppendLine("version 1").AppendLine("nodes").AppendLine("0 \"root\" -1").AppendLine("end")
                      .AppendLine("skeleton").AppendLine("time 0").AppendLine("0 0 0 0 0 0 0").AppendLine("end").AppendLine("triangles");
                }
                vertexKeys.UnionWith(keys);
                partMaterials.UnionWith(tileMaterials);
                foreach (var line in lines) {
                    sb.AppendLine(line);
                    if (line.StartsWith("0 ")) {
                        var f = line.Split(' ');
                        var p = new Vec3(-Vec3.D(f[2]), Vec3.D(f[1]), Vec3.D(f[3]));
                        part.Min = new Vec3(Math.Min(part.Min.X, p.X), Math.Min(part.Min.Y, p.Y), Math.Min(part.Min.Z, p.Z));
                        part.Max = new Vec3(Math.Max(part.Max.X, p.X), Math.Max(part.Max.Y, p.Y), Math.Max(part.Max.Z, p.Z));
                    }
                }
                part.Triangles += lines.Count / 4;
            }
            if (part != null) { sb.AppendLine("end"); part.Smd = sb.ToString(); part.Vertices = vertexKeys.Count; parts.Add(part); }
            return parts;
        }

        static StringBuilder BeginSmd() {
            var sb = new StringBuilder();
            sb.AppendLine("version 1").AppendLine("nodes").AppendLine("0 \"root\" -1").AppendLine("end")
              .AppendLine("skeleton").AppendLine("time 0").AppendLine("0 0 0 0 0 0 0").AppendLine("end").AppendLine("triangles");
            return sb;
        }

        // Snow overlay: every upward-facing renderable triangle of the recipe, lifted along +Z and mapped with one
        // planar snow material, so the runtime can fade settled snow onto roofs, streets, and ground.
        public List<CellModelPart> BuildSnowParts(string recipePath, double scale, Dictionary<string, MaterialInfo> materials, int maxPartVertices, string snowMaterial, double minNormalZ, double lift, double textureWorldSize) {
            var parts = new List<CellModelPart>();
            StringBuilder sb = null; CellModelPart part = null; int vertices = 0;
            foreach (var placement in ReadInstances(recipePath)) {
                if (!File.Exists(placement.File)) continue;
                var mesh = GetTile(placement.File);
                foreach (var tri in mesh.Triangles) {
                    MaterialInfo info;
                    if (!materials.TryGetValue(tri.Material, out info) || info == null) continue;
                    var n = new Vec3[3];
                    var w = new Vec3[3];
                    for (int k = 0; k < 3; k++) {
                        n[k] = Rotate(tri.N[k], placement.Angles).Normalized();
                        w[k] = Rotate(tri.P[k], placement.Angles) + placement.Origin;
                    }
                    var face = (w[1] - w[0]).Cross(w[2] - w[0]);
                    if (face.Length < 1e-6) continue;
                    var average = (n[0] + n[1] + n[2]).Normalized();
                    if (face.Dot(average) < 0) face = face * -1;
                    if (face.Normalized().Z < minNormalZ) continue;
                    if (part == null || vertices + 3 > maxPartVertices) {
                        if (part != null) { sb.AppendLine("end"); part.Smd = sb.ToString(); part.Vertices = vertices; parts.Add(part); }
                        part = new CellModelPart { Min = new Vec3(double.MaxValue, double.MaxValue, double.MaxValue), Max = new Vec3(double.MinValue, double.MinValue, double.MinValue) };
                        sb = BeginSmd();
                        vertices = 0;
                    }
                    sb.AppendLine(snowMaterial);
                    for (int k = 0; k < 3; k++) {
                        var p = new Vec3(w[k].X, w[k].Y, w[k].Z + lift) * scale;
                        double u = w[k].X / textureWorldSize;
                        double v = w[k].Y / textureWorldSize;
                        sb.AppendLine("0 " + F(p.Y) + " " + F(-p.X) + " " + F(p.Z) + " " + F(n[k].Y) + " " + F(-n[k].X) + " " + F(n[k].Z) + " " + F(u) + " " + F(v));
                        part.Min = new Vec3(Math.Min(part.Min.X, p.X), Math.Min(part.Min.Y, p.Y), Math.Min(part.Min.Z, p.Z));
                        part.Max = new Vec3(Math.Max(part.Max.X, p.X), Math.Max(part.Max.Y, p.Y), Math.Max(part.Max.Z, p.Z));
                    }
                    vertices += 3;
                    part.Triangles++;
                }
            }
            if (part != null) { sb.AppendLine("end"); part.Smd = sb.ToString(); part.Vertices = vertices; parts.Add(part); }
            return parts;
        }

        // Source AngleMatrix (pitch, yaw, roll) as a 3x3 rotation, and its inverse MatrixAngles.
        static double[,] AngleMatrix(Vec3 angles) {
            var f = Rotate(new Vec3(1, 0, 0), angles); var l = Rotate(new Vec3(0, 1, 0), angles); var u = Rotate(new Vec3(0, 0, 1), angles);
            return new double[,] { { f.X, l.X, u.X }, { f.Y, l.Y, u.Y }, { f.Z, l.Z, u.Z } };
        }

        static Vec3 ComposeAngles(Vec3 outer, Vec3 inner) {
            var a = AngleMatrix(outer); var b = AngleMatrix(inner); var m = new double[3, 3];
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) m[i, j] = a[i, 0] * b[0, j] + a[i, 1] * b[1, j] + a[i, 2] * b[2, j];
            double xy = Math.Sqrt(m[0, 0] * m[0, 0] + m[1, 0] * m[1, 0]);
            double yaw, pitch, roll;
            if (xy > 0.001) {
                yaw = Math.Atan2(m[1, 0], m[0, 0]); pitch = Math.Atan2(-m[2, 0], xy); roll = Math.Atan2(m[2, 1], m[2, 2]);
            } else {
                yaw = Math.Atan2(-m[0, 1], m[1, 1]); pitch = Math.Atan2(-m[2, 0], xy); roll = 0;
            }
            const double deg = 180.0 / Math.PI;
            return new Vec3(pitch * deg, yaw * deg, roll * deg);
        }

        // Small deterministic generator so a recipe always produces the same detail, independent of .NET hashing.
        sealed class Lcg {
            uint state;
            public Lcg(string key) { state = 2166136261; foreach (char c in key) { state ^= c; state *= 16777619; } if (state == 0) state = 1; }
            public double Next() { state = state * 1664525 + 1013904223; return (state >> 8) / 16777216.0; }
        }

        // Skybox set dressing for one recipe: authored tile props that read at skybox distance, extra wrecks parked in
        // road lanes to break long sightlines, and fire candidates (wrecks and rooftops) the runtime may set burning.
        // Props are emitted in recipe (world) space; kind 0 = scenery, 1 = authored vehicle, 2 = generated wreck.
        public RecipeDetail BuildDetail(string recipePath, string propPattern, string vehiclePattern, string roadMaterial, string[] carModels, double carSpacing, double carChance, double roofMinHeight) {
            var detail = new RecipeDetail();
            var propRx = new System.Text.RegularExpressions.Regex(propPattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var vehicleRx = new System.Text.RegularExpressions.Regex(vehiclePattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var random = new Lcg(Path.GetFileNameWithoutExtension(recipePath).ToLowerInvariant());
            foreach (var placement in ReadInstances(recipePath)) {
                if (!File.Exists(placement.File)) continue;
                var tile = GetTile(placement.File);
                var occupied = new List<Vec3>();
                foreach (var prop in tile.Props) {
                    bool vehicle = vehicleRx.IsMatch(prop.Model);
                    if (!vehicle && !propRx.IsMatch(prop.Model)) continue;
                    var origin = Rotate(prop.Origin, placement.Angles) + placement.Origin;
                    detail.Props.Add(new SkyProp { Model = prop.Model, Origin = origin, Angles = ComposeAngles(placement.Angles, prop.Angles), Skin = prop.Skin, Kind = vehicle ? 1 : 0 });
                    if (vehicle) {
                        occupied.Add(prop.Origin);
                        detail.Fires.Add(new SkyFire { Origin = origin, Kind = 1 });
                    }
                }
                if (carModels.Length > 0 && carChance > 0) {
                    foreach (var face in tile.UpFaces) {
                        if (!string.Equals(face.Material, roadMaterial, StringComparison.OrdinalIgnoreCase)) continue;
                        double width = face.MaxX - face.MinX, depth = face.MaxY - face.MinY;
                        bool alongX = width >= depth;
                        double length = Math.Max(width, depth), across = Math.Min(width, depth);
                        if (length < 256 || across < 96) continue;
                        int slots = Math.Max(1, (int)(length / carSpacing));
                        for (int slot = 0; slot < slots; slot++) {
                            double roll = random.Next(), along = random.Next(), side = random.Next(), jitter = random.Next(), turn = random.Next(), pick = random.Next();
                            if (roll >= carChance) continue;
                            double t = (slot + 0.25 + along * 0.5) / slots;
                            // Two-lane carriageways park the wreck in one lane; narrow strips keep it centred.
                            double lateral = across >= 200 ? (side < 0.5 ? -0.25 : 0.25) * across : 0;
                            lateral += (jitter - 0.5) * across * 0.1;
                            var local = alongX
                                ? new Vec3(face.MinX + t * width, (face.MinY + face.MaxY) * 0.5 + lateral, face.Z)
                                : new Vec3((face.MinX + face.MaxX) * 0.5 + lateral, face.MinY + t * depth, face.Z);
                            bool blocked = false;
                            foreach (var other in occupied) {
                                double dx = other.X - local.X, dy = other.Y - local.Y;
                                if (dx * dx + dy * dy < 220 * 220) { blocked = true; break; }
                            }
                            if (blocked) continue;
                            occupied.Add(local);
                            double yaw = (alongX ? 0 : 90) + (lateral < 0 ? 180 : 0);
                            // Most wrecks sit roughly in lane; some were abandoned skewed across it.
                            yaw += turn < 0.2 ? (turn < 0.1 ? -1 : 1) * (25 + turn * 300) : (turn - 0.6) * 20;
                            var origin = Rotate(local, placement.Angles) + placement.Origin;
                            string model = carModels[Math.Min(carModels.Length - 1, (int)(pick * carModels.Length))];
                            detail.Props.Add(new SkyProp { Model = model, Origin = origin, Angles = ComposeAngles(placement.Angles, new Vec3(0, yaw, 0)), Skin = (int)(jitter * 3), Kind = 2 });
                            detail.Fires.Add(new SkyFire { Origin = origin, Kind = 1 });
                        }
                    }
                }
                UpFace roof = null;
                foreach (var face in tile.UpFaces) {
                    if (face.Z < roofMinHeight || face.Material.StartsWith("TOOLS/", StringComparison.OrdinalIgnoreCase)) continue;
                    if ((face.MaxX - face.MinX) < 96 || (face.MaxY - face.MinY) < 96) continue;
                    if (roof == null || face.Z > roof.Z) roof = face;
                }
                if (roof != null) {
                    var local = new Vec3((roof.MinX + roof.MaxX) * 0.5, (roof.MinY + roof.MaxY) * 0.5, roof.Z);
                    detail.Fires.Add(new SkyFire { Origin = Rotate(local, placement.Angles) + placement.Origin, Kind = 2 });
                }
            }
            return detail;
        }
    }

    public sealed class SkyProp { public string Model; public Vec3 Origin; public Vec3 Angles; public int Skin; public int Kind; }
    public sealed class SkyFire { public Vec3 Origin; public int Kind; }
    public sealed class RecipeDetail {
        public readonly List<SkyProp> Props = new List<SkyProp>();
        public readonly List<SkyFire> Fires = new List<SkyFire>();
    }
}
'@
}

Export-ModuleMember
