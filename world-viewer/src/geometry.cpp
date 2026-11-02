#include "geometry.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <sstream>

#include "keyvalues.hpp"

namespace zmv {

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kClipEpsilon = 0.01;
constexpr double kWorldExtent = 262144.0;

struct V3 {
    double x = 0, y = 0, z = 0;
};
V3 operator+(V3 a, V3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
V3 operator-(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
V3 operator*(V3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
double Dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
V3 Cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
double Length(V3 a) { return std::sqrt(Dot(a, a)); }
V3 Normalize(V3 a) {
    const double l = Length(a);
    return l > 1e-12 ? a * (1.0 / l) : V3{0, 0, 1};
}

struct Plane {
    V3 n;
    double d = 0;
};

using Winding = std::vector<V3>;

bool ParsePlanePoints(const std::string& text, V3 p[3]) {
    std::string s = text;
    for (char& c : s) {
        if (c == '(' || c == ')') c = ' ';
    }
    std::istringstream in(s);
    for (int i = 0; i < 3; ++i) {
        if (!(in >> p[i].x >> p[i].y >> p[i].z)) return false;
    }
    return true;
}

bool ParseVec(const std::string& text, V3& v) {
    std::string s = text;
    for (char& c : s) {
        if (c == '[' || c == ']') c = ' ';
    }
    std::istringstream in(s);
    return static_cast<bool>(in >> v.x >> v.y >> v.z);
}

std::vector<double> ParseNumbers(const std::string& text) {
    std::vector<double> out;
    std::istringstream in(text);
    double v;
    while (in >> v) out.push_back(v);
    return out;
}

Winding BaseWinding(const Plane& plane) {
    V3 up{0, 0, 1};
    if (std::fabs(plane.n.z) > 0.9) up = {1, 0, 0};
    const V3 right = Normalize(Cross(up, plane.n));
    up = Normalize(Cross(plane.n, right));
    const V3 origin = plane.n * plane.d;
    const V3 r = right * kWorldExtent;
    const V3 u = up * kWorldExtent;
    return {origin - r + u, origin + r + u, origin + r - u, origin - r - u};
}

Winding Clip(const Winding& in, const Plane& plane) {
    Winding out;
    const size_t count = in.size();
    for (size_t i = 0; i < count; ++i) {
        const V3& a = in[i];
        const V3& b = in[(i + 1) % count];
        const double da = Dot(a, plane.n) - plane.d;
        const double db = Dot(b, plane.n) - plane.d;
        if (da <= kClipEpsilon) out.push_back(a);
        if ((da > kClipEpsilon && db < -kClipEpsilon) || (da < -kClipEpsilon && db > kClipEpsilon)) {
            const double t = da / (da - db);
            out.push_back(a + (b - a) * t);
        }
    }
    return out;
}

V3 NewellNormal(const Winding& w) {
    V3 n;
    for (size_t i = 0; i < w.size(); ++i) {
        const V3& a = w[i];
        const V3& b = w[(i + 1) % w.size()];
        n.x += (a.y - b.y) * (a.z + b.z);
        n.y += (a.z - b.z) * (a.x + b.x);
        n.z += (a.x - b.x) * (a.y + b.y);
    }
    return n;
}

// Material plus Source texture axes for one brush side.
struct Surface {
    Rgb color;
    int tile = -1;
    AlphaMode alpha = AlphaMode::Opaque;
    V3 uAxis{1, 0, 0}, vAxis{0, -1, 0};
    double uShift = 0, vShift = 0, uScale = 0.25, vScale = 0.25;
    double texW = 512, texH = 512;
    void UV(const V3& p, double& u, double& v) const {
        u = (Dot(p, uAxis) / uScale + uShift) / texW;
        v = (Dot(p, vAxis) / vScale + vShift) / texH;
    }
};

bool ParseTexAxis(const std::string* text, V3& axis, double& shift, double& scale) {
    if (!text) return false;
    std::string s = *text;
    for (char& c : s) {
        if (c == '[' || c == ']') c = ' ';
    }
    const auto values = ParseNumbers(s);
    if (values.size() < 5) return false;
    axis = {values[0], values[1], values[2]};
    shift = values[3];
    scale = std::fabs(values[4]) < 1e-6 ? 1.0 : values[4];
    return true;
}

void EmitPolygon(MeshData& mesh, const Winding& w, V3 normal, const Surface& surf) {
    const double n[3] = {normal.x, normal.y, normal.z};
    for (size_t i = 1; i + 1 < w.size(); ++i) {
        const V3* tri[3] = {&w[0], &w[i], &w[i + 1]};
        for (const V3* v : tri) {
            const double p[3] = {v->x, v->y, v->z};
            double u, t;
            surf.UV(*v, u, t);
            mesh.AddVertex(p, n, surf.color, u, t, surf.tile, surf.alpha);
        }
    }
}

bool IsShellMaterial(const std::string& lower) {
    return lower == "halflife/black" || lower == "tools/toolsblack" || lower == "tools/toolsblack_noportal";
}

bool IsSkippedBrushEntity(const std::string& cls) {
    const std::string c = ToLower(cls);
    if (c.rfind("trigger_", 0) == 0) return true;
    if (c.rfind("func_areaportal", 0) == 0) return true;
    static const char* skipped[] = {"func_occluder", "func_vehicleclip", "func_clip_vphysics", "func_viscluster",
                                    "func_ladderendpoint", "func_buyzone", "func_bomb_target", "func_hostage_rescue"};
    for (const char* s : skipped) {
        if (c == s) return true;
    }
    return false;
}

bool EmitDisplacement(MeshData& mesh, const Winding& face, const Plane& plane, const KVNode& disp, const Surface& surf) {
    if (face.size() != 4) return false;
    int power = 0;
    if (const std::string* p = disp.Get("power")) power = std::atoi(p->c_str());
    if (power < 1 || power > 4) return false;
    const int n = 1 << power;
    const int width = n + 1;

    Winding w = face;
    if (Dot(NewellNormal(w), plane.n) > 0) std::reverse(w.begin(), w.end());
    V3 start;
    if (const std::string* sp = disp.Get("startposition")) ParseVec(*sp, start);
    size_t first = 0;
    double best = 1e300;
    for (size_t i = 0; i < 4; ++i) {
        const double d = Length(w[i] - start);
        if (d < best) {
            best = d;
            first = i;
        }
    }
    V3 s[4];
    for (size_t i = 0; i < 4; ++i) s[i] = w[(first + i) % 4];

    std::vector<V3> normals(width * width, V3{0, 0, 0});
    std::vector<double> distances(width * width, 0.0);
    std::vector<V3> offsets(width * width, V3{0, 0, 0});
    const KVNode* normalsNode = disp.Child("normals");
    const KVNode* distancesNode = disp.Child("distances");
    const KVNode* offsetsNode = disp.Child("offsets");
    for (int i = 0; i < width; ++i) {
        const std::string row = "row" + std::to_string(i);
        if (normalsNode) {
            if (const std::string* r = normalsNode->Get(row)) {
                const auto values = ParseNumbers(*r);
                for (int j = 0; j < width && j * 3 + 2 < static_cast<int>(values.size()); ++j) {
                    normals[i * width + j] = {values[j * 3], values[j * 3 + 1], values[j * 3 + 2]};
                }
            }
        }
        if (distancesNode) {
            if (const std::string* r = distancesNode->Get(row)) {
                const auto values = ParseNumbers(*r);
                for (int j = 0; j < width && j < static_cast<int>(values.size()); ++j) distances[i * width + j] = values[j];
            }
        }
        if (offsetsNode) {
            if (const std::string* r = offsetsNode->Get(row)) {
                const auto values = ParseNumbers(*r);
                for (int j = 0; j < width && j * 3 + 2 < static_cast<int>(values.size()); ++j) {
                    offsets[i * width + j] = {values[j * 3], values[j * 3 + 1], values[j * 3 + 2]};
                }
            }
        }
    }
    double elevation = 0;
    if (const std::string* e = disp.Get("elevation")) elevation = std::atof(e->c_str());

    std::vector<V3> verts(width * width);
    std::vector<std::array<double, 2>> uvs(width * width);
    for (int i = 0; i < width; ++i) {
        const double ti = static_cast<double>(i) / n;
        const V3 end0 = s[0] + (s[1] - s[0]) * ti;
        const V3 end1 = s[3] + (s[2] - s[3]) * ti;
        for (int j = 0; j < width; ++j) {
            const double tj = static_cast<double>(j) / n;
            const int idx = i * width + j;
            const V3 flat = end0 + (end1 - end0) * tj;
            // Source maps displacement textures from the undisplaced face.
            surf.UV(flat, uvs[idx][0], uvs[idx][1]);
            verts[idx] = flat + normals[idx] * distances[idx] + offsets[idx] + plane.n * elevation;
        }
    }

    std::vector<std::array<int, 3>> tris;
    tris.reserve(n * n * 2);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            const int a = i * width + j, b = a + 1, c = a + width, d = c + 1;
            if (((i + j) & 1) == 0) {
                tris.push_back({a, c, b});
                tris.push_back({b, c, d});
            } else {
                tris.push_back({a, c, d});
                tris.push_back({a, d, b});
            }
        }
    }
    std::vector<V3> smooth(width * width, V3{0, 0, 0});
    for (auto& t : tris) {
        V3 cr = Cross(verts[t[1]] - verts[t[0]], verts[t[2]] - verts[t[0]]);
        if (Dot(cr, plane.n) < 0) {
            std::swap(t[1], t[2]);
            cr = cr * -1.0;
        }
        for (int k : t) smooth[k] = smooth[k] + cr;
    }
    for (const auto& t : tris) {
        for (int k : t) {
            const V3 nn = Normalize(Length(smooth[k]) > 1e-9 ? smooth[k] : plane.n);
            const double p[3] = {verts[k].x, verts[k].y, verts[k].z};
            const double nv[3] = {nn.x, nn.y, nn.z};
            mesh.AddVertex(p, nv, surf.color, uvs[k][0], uvs[k][1], surf.tile, surf.alpha);
        }
    }
    return true;
}

void EmitSolid(const KVNode& solid, VmfModel& model, MaterialColors& colors) {
    struct Side {
        Plane plane;
        std::string material;
        const KVNode* disp = nullptr;
        const KVNode* node = nullptr;
    };
    std::vector<Side> sides;
    bool hasDisp = false;
    for (const KVNode& child : solid.children) {
        if (!IEquals(child.name, "side")) continue;
        const std::string* planeText = child.Get("plane");
        if (!planeText) continue;
        V3 p[3];
        if (!ParsePlanePoints(*planeText, p)) {
            ++model.failedSides;
            continue;
        }
        Side side;
        const V3 normal = Cross(p[0] - p[1], p[2] - p[1]);
        if (Length(normal) < 1e-9) {
            ++model.failedSides;
            continue;
        }
        side.plane.n = Normalize(normal);
        side.plane.d = Dot(side.plane.n, p[1]);
        if (const std::string* m = child.Get("material")) side.material = ToLower(*m);
        side.disp = child.Child("dispinfo");
        side.node = &child;
        hasDisp = hasDisp || side.disp != nullptr;
        sides.push_back(std::move(side));
    }
    if (sides.size() < 4) return;
    ++model.brushes;

    for (size_t i = 0; i < sides.size(); ++i) {
        const Side& side = sides[i];
        if (hasDisp && !side.disp) continue;
        const bool shell = IsShellMaterial(side.material);
        if (!side.disp && !shell && IsInvisibleToolMaterial(side.material)) continue;
        Winding w = BaseWinding(side.plane);
        for (size_t j = 0; j < sides.size() && w.size() >= 3; ++j) {
            if (j == i) continue;
            w = Clip(w, sides[j].plane);
        }
        if (w.size() < 3) continue;
        const MaterialInfo& info = colors.Info(side.material);
        Surface surf;
        surf.color = info.color;
        if (!shell && info.tile >= 0 && ParseTexAxis(side.node->Get("uaxis"), surf.uAxis, surf.uShift, surf.uScale) &&
            ParseTexAxis(side.node->Get("vaxis"), surf.vAxis, surf.vShift, surf.vScale)) {
            surf.tile = info.tile;
            surf.alpha = info.alpha;
            surf.texW = info.width;
            surf.texH = info.height;
        }
        if (side.disp) {
            if (EmitDisplacement(model.mesh, w, side.plane, *side.disp, surf)) {
                ++model.displacements;
                continue;
            }
            ++model.failedSides;
        }
        if (Dot(NewellNormal(w), side.plane.n) < 0) std::reverse(w.begin(), w.end());
        EmitPolygon(shell ? model.shell : model.mesh, w, side.plane.n, surf);
    }
}

void EmitBrushes(const KVNode& owner, VmfModel& model, MaterialColors& colors) {
    for (const KVNode& child : owner.children) {
        if (IEquals(child.name, "solid")) EmitSolid(child, model, colors);
    }
}

}  // namespace

Mat4 Mat4::Translation(double x, double y, double z) {
    Mat4 r;
    r.m[12] = static_cast<float>(x);
    r.m[13] = static_cast<float>(y);
    r.m[14] = static_cast<float>(z);
    return r;
}

Mat4 Mat4::FromSourceAngles(double pitch, double yaw, double roll, double ox, double oy, double oz) {
    const double p = pitch * kPi / 180.0, y = yaw * kPi / 180.0, r = roll * kPi / 180.0;
    const double sp = std::sin(p), cp = std::cos(p), sy = std::sin(y), cy = std::cos(y), sr = std::sin(r), cr = std::cos(r);
    Mat4 out;
    // Column 0
    out.m[0] = static_cast<float>(cp * cy);
    out.m[1] = static_cast<float>(cp * sy);
    out.m[2] = static_cast<float>(-sp);
    // Column 1
    out.m[4] = static_cast<float>(sp * sr * cy - cr * sy);
    out.m[5] = static_cast<float>(sp * sr * sy + cr * cy);
    out.m[6] = static_cast<float>(sr * cp);
    // Column 2
    out.m[8] = static_cast<float>(sp * cr * cy + sr * sy);
    out.m[9] = static_cast<float>(sp * cr * sy - sr * cy);
    out.m[10] = static_cast<float>(cr * cp);
    out.m[12] = static_cast<float>(ox);
    out.m[13] = static_cast<float>(oy);
    out.m[14] = static_cast<float>(oz);
    return out;
}

Mat4 Mat4::operator*(const Mat4& rhs) const {
    Mat4 r;
    for (int c = 0; c < 4; ++c) {
        for (int row = 0; row < 4; ++row) {
            double sum = 0;
            for (int k = 0; k < 4; ++k) sum += static_cast<double>(m[k * 4 + row]) * rhs.m[c * 4 + k];
            r.m[c * 4 + row] = static_cast<float>(sum);
        }
    }
    return r;
}

std::array<float, 3> Mat4::TransformPoint(float x, float y, float z) const {
    return {m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14]};
}

void MeshData::AddVertex(const double p[3], const double n[3], Rgb c, double u, double v, int tile, AlphaMode alpha) {
    for (int i = 0; i < 3; ++i) {
        const float f = static_cast<float>(p[i]);
        positions.push_back(f);
        normals.push_back(static_cast<float>(n[i]));
        boundsMin[i] = std::min(boundsMin[i], f);
        boundsMax[i] = std::max(boundsMax[i], f);
    }
    colors.push_back(c.r);
    colors.push_back(c.g);
    colors.push_back(c.b);
    colors.push_back(255);
    uvs.push_back(static_cast<float>(u));
    uvs.push_back(static_cast<float>(v));
    surface.push_back(static_cast<float>(tile));
    surface.push_back(static_cast<float>(alpha));
}

namespace {

// VRAD-style "_light" parsing: gamma-correct 0..255 colour, scaled by the 4th value / 255.
std::array<float, 3> ParseLightColor(const std::string* text, std::array<float, 3> fallback) {
    if (!text) return fallback;
    const auto v = ParseNumbers(*text);
    if (v.size() < 3) return fallback;
    const double scale = v.size() >= 4 ? v[3] / 255.0 : 1.0;
    std::array<float, 3> out{};
    for (int i = 0; i < 3; ++i) out[i] = static_cast<float>(std::pow(std::max(0.0, v[i]) / 255.0, 2.2) * scale);
    return out;
}

double NumberKey(const KVNode& e, const char* key, double fallback = 0) {
    const std::string* v = e.Get(key);
    return v ? std::atof(v->c_str()) : fallback;
}

// VRAD SetupLightNormalFromProps.
V3 LightDirection(const KVNode& e) {
    V3 angles;
    if (const std::string* a = e.Get("angles")) ParseVec(*a, angles);
    double yaw = NumberKey(e, "angle");
    V3 dir;
    if (yaw == -1) {
        dir = {0, 0, 1};
    } else if (yaw == -2) {
        dir = {0, 0, -1};
    } else {
        if (yaw == 0) yaw = angles.y;
        dir = {std::cos(yaw * kPi / 180.0), std::sin(yaw * kPi / 180.0), 0};
    }
    double pitch = NumberKey(e, "pitch");
    if (pitch == 0) pitch = angles.x;
    const double p = pitch * kPi / 180.0;
    dir.z = std::sin(p);
    dir.x *= std::cos(p);
    dir.y *= std::cos(p);
    return Normalize(dir);
}

bool ParseLight(const KVNode& e, const std::string& cls, LightDef& out) {
    if (cls == "light_environment") {
        out.type = LightType::Environment;
        out.color = ParseLightColor(e.Get("_light"), {0.78f, 0.78f, 0.78f});
        const std::array<float, 3> half{out.color[0] * 0.5f, out.color[1] * 0.5f, out.color[2] * 0.5f};
        out.ambient = ParseLightColor(e.Get("_ambient"), half);
    } else if (cls == "light" || cls == "light_spot") {
        out.type = cls == "light_spot" ? LightType::Spot : LightType::Point;
        out.color = ParseLightColor(e.Get("_light"), {0.0f, 0.0f, 0.0f});
        double c = NumberKey(e, "_constant_attn"), l = NumberKey(e, "_linear_attn"), q = NumberKey(e, "_quadratic_attn");
        double cutoff = NumberKey(e, "_distance");
        const double d50 = NumberKey(e, "_fifty_percent_distance");
        double scale;
        if (d50 > 0) {
            // Approximation of VRAD's fifty/zero-percent falloff: 1/(1 + d^2/d50^2), cut off at zero-percent.
            c = 1;
            l = 0;
            q = 1.0 / (d50 * d50);
            const double zero = NumberKey(e, "_zero_percent_distance");
            cutoff = zero > d50 ? zero : d50 * 2;
            scale = c + q * 10000.0;
        } else {
            if (c == 0 && l == 0 && q == 0) c = 1;
            scale = c + 100.0 * l + 10000.0 * q;
        }
        for (float& ch : out.color) ch = static_cast<float>(ch * scale);
        out.constant = static_cast<float>(c);
        out.linear = static_cast<float>(l);
        out.quadratic = static_cast<float>(q);
        out.cutoff = static_cast<float>(std::max(0.0, cutoff));
        if (out.type == LightType::Spot) {
            double inner = NumberKey(e, "_inner_cone", 10);
            double outer = NumberKey(e, "_cone", inner);
            inner = std::min(90.0, std::max(0.0, inner));
            outer = std::min(90.0, std::max(inner, outer));
            out.cosInner = static_cast<float>(std::cos(inner * kPi / 180.0));
            out.cosOuter = static_cast<float>(std::cos(outer * kPi / 180.0));
            out.exponent = static_cast<float>(NumberKey(e, "_exponent", 1));
        }
    } else {
        return false;
    }
    if (out.type != LightType::Point) {
        const V3 d = LightDirection(e);
        out.direction = {static_cast<float>(d.x), static_cast<float>(d.y), static_cast<float>(d.z)};
    }
    V3 origin;
    if (const std::string* o = e.Get("origin")) ParseVec(*o, origin);
    out.position = {static_cast<float>(origin.x), static_cast<float>(origin.y), static_cast<float>(origin.z)};
    return true;
}

}  // namespace

VmfModel LoadVmf(const std::filesystem::path& path, MaterialColors& colors, const VmfLoadOptions& options) {
    VmfModel model;
    std::string text;
    if (!ReadFileBytes(path, text)) {
        model.error = "cannot read " + path.string();
        return model;
    }
    const KVNode root = ParseKeyValues(text);
    for (const KVNode& block : root.children) {
        if (IEquals(block.name, "world")) {
            EmitBrushes(block, model, colors);
            continue;
        }
        if (!IEquals(block.name, "entity")) continue;
        const std::string* clsPtr = block.Get("classname");
        const std::string cls = clsPtr ? ToLower(*clsPtr) : std::string();
        if (cls == "func_instance") {
            const std::string* file = block.Get("file");
            if (!file || file->empty()) continue;
            const std::string lowerFile = ToLower(*file);
            const std::string* targetname = block.Get("targetname");
            if (options.skipSkyboxRoom &&
                (lowerFile.find("skybox_room") != std::string::npos ||
                 (targetname && ToLower(*targetname).find("skybox_room") != std::string::npos))) {
                continue;
            }
            V3 origin, angles;
            if (const std::string* o = block.Get("origin")) ParseVec(*o, origin);
            if (const std::string* a = block.Get("angles")) ParseVec(*a, angles);
            InstanceRef ref;
            ref.rawFile = *file;
            std::string normalized = *file;
            std::replace(normalized.begin(), normalized.end(), '\\', '/');
            ref.file = (path.parent_path() / std::filesystem::path(normalized)).lexically_normal();
            ref.local = Mat4::FromSourceAngles(angles.x, angles.y, angles.z, origin.x, origin.y, origin.z);
            if (targetname) ref.targetname = *targetname;
            ref.origin = {static_cast<float>(origin.x), static_cast<float>(origin.y), static_cast<float>(origin.z)};
            ref.angles = {static_cast<float>(angles.x), static_cast<float>(angles.y), static_cast<float>(angles.z)};
            model.instances.push_back(std::move(ref));
            continue;
        }
        if (cls.rfind("prop_", 0) == 0) {
            ++model.props;
            const std::string* mdl = block.Get("model");
            if (!mdl || mdl->empty()) continue;
            V3 origin, angles;
            if (const std::string* o = block.Get("origin")) ParseVec(*o, origin);
            if (const std::string* a = block.Get("angles")) ParseVec(*a, angles);
            double scale = 1;
            for (const char* key : {"modelscale", "uniformscale"}) {
                if (const std::string* s = block.Get(key)) {
                    const double v = std::atof(s->c_str());
                    if (v > 0) {
                        scale = v;
                        break;
                    }
                }
            }
            PropRef prop;
            prop.model = *mdl;
            if (const std::string* skin = block.Get("skin")) prop.skin = std::atoi(skin->c_str());
            Mat4 scaling;
            scaling.m[0] = scaling.m[5] = scaling.m[10] = static_cast<float>(scale);
            prop.local = Mat4::FromSourceAngles(angles.x, angles.y, angles.z, origin.x, origin.y, origin.z) * scaling;
            model.propRefs.push_back(std::move(prop));
            continue;
        }
        if (cls.rfind("light", 0) == 0) {
            LightDef light;
            if (ParseLight(block, cls, light)) model.lights.push_back(light);
            continue;
        }
        if (IsSkippedBrushEntity(cls)) continue;
        EmitBrushes(block, model, colors);
    }
    model.loaded = true;
    return model;
}

}  // namespace zmv
