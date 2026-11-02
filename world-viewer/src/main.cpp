// ZombieSim world viewer: renders a generated preview plan directly from its source VMFs.
#include <raylib.h>
#include <raymath.h>
#include <rlgl.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

#include "hammer.hpp"
#include "keyvalues.hpp"
#include "materials.hpp"
#include "scene.hpp"
#include "studio.hpp"
#include "vpk.hpp"

namespace fs = std::filesystem;
using namespace zmv;

namespace {

const char* kVertexShader = R"(#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;
uniform mat4 mvp;
out vec3 fragPos;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragUv;
flat out vec2 fragSurface;
void main() {
    vec4 world = instanceTransform * vec4(vertexPosition, 1.0);
    fragPos = world.xyz;
    fragNormal = mat3(instanceTransform) * vertexNormal;
    fragColor = vertexColor;
    fragUv = vertexTexCoord;
    fragSurface = vertexTexCoord2;
    gl_Position = mvp * world;
}
)";

// texture0 = material atlas, texture1 = light records (5 RGBA32F texels each), texture2 = light grid.
const char* kFragmentShader = R"(#version 330
in vec3 fragPos;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragUv;
flat in vec2 fragSurface;
uniform sampler2D texture0;
uniform sampler2D texture1;
uniform sampler2D texture2;
uniform vec3 viewPos;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float tint;
uniform int textured;
uniform int lit;
uniform vec4 atlas;        // columns, cell px, gutter px, tile px
uniform vec2 atlasSize;
uniform vec3 sunColor;     // linear, already zero at night
uniform vec3 ambientColor; // linear
uniform vec4 lightGrid;    // origin x, origin y, cell size, light count
uniform ivec2 lightGridSize;
out vec4 finalColor;

vec3 ToLinear(vec3 c) { return pow(c, vec3(2.2)); }

vec4 SampleTile(int tile) {
    float cols = atlas.x;
    vec2 cell = vec2(mod(float(tile), cols), floor(float(tile) / cols));
    vec2 texel = fragUv * atlas.w;
    vec2 dx = dFdx(texel), dy = dFdy(texel);
    float lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8));
    vec2 p = cell * atlas.y + atlas.z + fract(fragUv) * atlas.w;
    vec4 t = textureLod(texture0, p / atlasSize, clamp(lod, 0.0, 3.0));
    // Past the gutter-safe mip, fade to the material's average colour.
    t.rgb = mix(t.rgb, fragColor.rgb, smoothstep(3.0, 5.0, lod));
    return t;
}

vec3 PointLights(vec3 n) {
    if (lightGrid.w <= 0.0) return vec3(0.0);
    ivec2 g = ivec2(floor((fragPos.xy - lightGrid.xy) / lightGrid.z));
    if (g.x < 0 || g.y < 0 || g.x >= lightGridSize.x || g.y >= lightGridSize.y) return vec3(0.0);
    vec4 ids[2];
    ids[0] = texelFetch(texture2, ivec2(g.x * 2, g.y), 0);
    ids[1] = texelFetch(texture2, ivec2(g.x * 2 + 1, g.y), 0);
    vec3 sum = vec3(0.0);
    for (int k = 0; k < 8; ++k) {
        float fid = ids[k / 4][k % 4];
        if (fid < 0.0) break;
        int id = int(fid);
        ivec2 base = ivec2((id % 64) * 5, id / 64);
        vec4 a = texelFetch(texture1, base, 0);
        vec4 b = texelFetch(texture1, base + ivec2(1, 0), 0);
        vec4 c = texelFetch(texture1, base + ivec2(2, 0), 0);
        vec4 d = texelFetch(texture1, base + ivec2(3, 0), 0);
        vec4 e = texelFetch(texture1, base + ivec2(4, 0), 0);
        vec3 L = a.xyz - fragPos;
        float dist = max(length(L), 1.0);
        if (b.w > 0.0 && dist > b.w) continue;
        L /= dist;
        float ndl = max(dot(n, L), 0.0);
        if (ndl <= 0.0) continue;
        float atten = 1.0 / max(d.x + d.y * dist + d.z * dist * dist, 1e-4);
        if (a.w > 0.5) {
            float s = clamp((dot(-L, c.xyz) - e.y) / max(e.x - e.y, 1e-4), 0.0, 1.0);
            if (c.w != 0.0 && c.w != 1.0) s = pow(s, c.w);
            atten *= s;
        }
        sum += b.rgb * atten * ndl;
    }
    return sum;
}

void main() {
    vec3 n = normalize(fragNormal);
    if (!gl_FrontFacing) n = -n;
    vec3 albedo = fragColor.rgb;
    int tile = int(fragSurface.x + 0.5);
    if (textured == 1 && fragSurface.x >= 0.0) {
        vec4 t = SampleTile(tile);
        if (fragSurface.y > 1.5) { if (t.a < 0.3) discard; }
        else if (fragSurface.y > 0.5) { if (t.a < 0.5) discard; }
        albedo = t.rgb;
    }
    albedo *= tint;
    vec3 color;
    if (lit == 1) {
        vec3 a = ToLinear(albedo);
        vec3 light = ambientColor * mix(0.55, 1.0, n.z * 0.5 + 0.5);
        light += sunColor * (max(dot(n, sunDir), 0.0) + 0.12);
        light += PointLights(n);
        vec3 c = a * light;
        c = vec3(1.0) - exp(-c * 1.6);
        color = pow(c, vec3(1.0 / 2.2));
    } else {
        float sun = max(dot(n, sunDir), 0.0);
        vec3 hemi = mix(vec3(0.32, 0.30, 0.28), vec3(0.55, 0.60, 0.68), n.z * 0.5 + 0.5);
        color = albedo * (hemi + vec3(1.0, 0.95, 0.85) * sun * 0.75);
    }
    float d = length(fragPos - viewPos);
    float f = exp(-pow(d * fogDensity, 2.0));
    finalColor = vec4(mix(fogColor, color, f), 1.0);
}
)";

struct Options {
    fs::path plan;
    fs::path repo;
    fs::path screenshot;
    int frames = 10;
    int cellX = -1, cellY = -1;
    bool street = false;
    bool overview = false;
    bool noWindow = false;
    bool textured = true, lit = false, night = false;
    bool props = false;
    fs::path hammer;
    std::vector<std::string> models;    // --model diagnostics: load, report and exit
    int inspectX = -1, inspectY = -1;   // test hook: open the cell inspector on this cell
    int width = 1600, height = 900;
};

bool ParseArgs(int argc, char** argv, Options& o) {
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() -> const char* { return (i + 1 < argc) ? argv[++i] : nullptr; };
        if (a == "--plan") { const char* v = next(); if (!v) return false; o.plan = v; }
        else if (a == "--repo") { const char* v = next(); if (!v) return false; o.repo = v; }
        else if (a == "--screenshot") { const char* v = next(); if (!v) return false; o.screenshot = v; }
        else if (a == "--frames") { const char* v = next(); if (!v) return false; o.frames = std::max(1, std::atoi(v)); }
        else if (a == "--cell") {
            const char* x = next(); const char* y = next();
            if (!x || !y) return false;
            o.cellX = std::atoi(x); o.cellY = std::atoi(y);
        }
        else if (a == "--overview") o.overview = true;
        else if (a == "--street") o.street = true;
        else if (a == "--untextured") o.textured = false;
        else if (a == "--lit") o.lit = true;
        else if (a == "--night") { o.lit = true; o.night = true; }
        else if (a == "--props") o.props = true;
        else if (a == "--hammer") { const char* v = next(); if (!v) return false; o.hammer = v; }
        else if (a == "--model") { const char* v = next(); if (!v) return false; o.models.push_back(v); }
        else if (a == "--inspect") {
            const char* x = next(); const char* y = next();
            if (!x || !y) return false;
            o.inspectX = std::atoi(x); o.inspectY = std::atoi(y);
        }
        else if (a == "--stats") o.noWindow = true;
        else if (a == "--size") {
            const char* w = next(); const char* h = next();
            if (!w || !h) return false;
            o.width = std::atoi(w); o.height = std::atoi(h);
        }
        else return false;
    }
    return !o.plan.empty() || !o.models.empty();
}

Matrix ToRay(const Mat4& m) {
    Matrix r;
    r.m0 = m.m[0]; r.m1 = m.m[1]; r.m2 = m.m[2]; r.m3 = m.m[3];
    r.m4 = m.m[4]; r.m5 = m.m[5]; r.m6 = m.m[6]; r.m7 = m.m[7];
    r.m8 = m.m[8]; r.m9 = m.m[9]; r.m10 = m.m[10]; r.m11 = m.m[11];
    r.m12 = m.m[12]; r.m13 = m.m[13]; r.m14 = m.m[14]; r.m15 = m.m[15];
    return r;
}

Mesh Upload(const MeshData& data) {
    Mesh mesh{};
    mesh.vertexCount = static_cast<int>(data.positions.size() / 3);
    mesh.triangleCount = mesh.vertexCount / 3;
    mesh.vertices = static_cast<float*>(RL_MALLOC(data.positions.size() * sizeof(float)));
    std::memcpy(mesh.vertices, data.positions.data(), data.positions.size() * sizeof(float));
    mesh.normals = static_cast<float*>(RL_MALLOC(data.normals.size() * sizeof(float)));
    std::memcpy(mesh.normals, data.normals.data(), data.normals.size() * sizeof(float));
    mesh.colors = static_cast<unsigned char*>(RL_MALLOC(data.colors.size()));
    std::memcpy(mesh.colors, data.colors.data(), data.colors.size());
    mesh.texcoords = static_cast<float*>(RL_MALLOC(data.uvs.size() * sizeof(float)));
    std::memcpy(mesh.texcoords, data.uvs.data(), data.uvs.size() * sizeof(float));
    mesh.texcoords2 = static_cast<float*>(RL_MALLOC(data.surface.size() * sizeof(float)));
    std::memcpy(mesh.texcoords2, data.surface.data(), data.surface.size() * sizeof(float));
    UploadMesh(&mesh, false);
    // GPU copies are enough; release CPU arrays to keep memory down.
    RL_FREE(mesh.vertices); mesh.vertices = nullptr;
    RL_FREE(mesh.normals); mesh.normals = nullptr;
    RL_FREE(mesh.colors); mesh.colors = nullptr;
    RL_FREE(mesh.texcoords); mesh.texcoords = nullptr;
    RL_FREE(mesh.texcoords2); mesh.texcoords2 = nullptr;
    return mesh;
}

struct Atlas {
    Texture2D texture{};
    int columns = 1, cell = 1, gutter = 0, tile = 1;
    int width = 1, height = 1;
};

// Packs every material tile into one mipmapped texture with wrapped gutters so tiling and filtering stay seamless.
Atlas BuildAtlas(const std::vector<std::vector<uint8_t>>& tiles) {
    Atlas a;
    const int src = MaterialColors::kTileSize;
    const int count = std::max<int>(1, static_cast<int>(tiles.size()));
    a.columns = 64;
    a.tile = src;
    a.gutter = 8;
    a.cell = a.tile + a.gutter * 2;
    auto rows = [&]() { return (count + a.columns - 1) / a.columns; };
    if (rows() * a.cell > 16384) {
        a.tile = src / 2;
        a.gutter = 4;
        a.cell = a.tile + a.gutter * 2;
    }
    a.width = a.columns * a.cell;
    a.height = std::max(1, rows()) * a.cell;
    std::vector<uint8_t> pixels(static_cast<size_t>(a.width) * a.height * 4, 128);
    const int step = src / a.tile;
    for (size_t t = 0; t < tiles.size(); ++t) {
        const auto& px = tiles[t];
        const int ox = static_cast<int>(t % a.columns) * a.cell;
        const int oy = static_cast<int>(t / a.columns) * a.cell;
        for (int y = 0; y < a.cell; ++y) {
            const int sy = ((y - a.gutter) % a.tile + a.tile) % a.tile * step;
            for (int x = 0; x < a.cell; ++x) {
                const int sx = ((x - a.gutter) % a.tile + a.tile) % a.tile * step;
                const uint8_t* s = &px[(static_cast<size_t>(sy) * src + sx) * 4];
                uint8_t* d = &pixels[(static_cast<size_t>(oy + y) * a.width + ox + x) * 4];
                std::memcpy(d, s, 4);
            }
        }
    }
    Image image{pixels.data(), a.width, a.height, 1, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8};
    a.texture = LoadTextureFromImage(image);
    GenTextureMipmaps(&a.texture);
    SetTextureFilter(a.texture, TEXTURE_FILTER_TRILINEAR);
    SetTextureWrap(a.texture, TEXTURE_WRAP_CLAMP);
    return a;
}

Texture2D FloatTexture(const std::vector<float>& rgba, int w, int h) {
    Texture2D t{};
    t.id = rlLoadTexture(rgba.data(), w, h, RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32, 1);
    t.width = w;
    t.height = h;
    t.mipmaps = 1;
    t.format = PIXELFORMAT_UNCOMPRESSED_R32G32B32A32;
    return t;
}

constexpr int kLightsPerRow = 64;
constexpr int kLightsPerCell = 8;

// Distance at which a light's contribution drops below `threshold`, capped by its cutoff.
float LightRange(const LightDef& l, float threshold = 0.01f) {
    const float intensity = std::max({l.color[0], l.color[1], l.color[2]});
    float range = 2048;
    if (intensity > 0) {
        const double target = intensity / threshold;  // c + l d + q d^2 = target
        if (l.quadratic > 0) {
            const double disc = l.linear * l.linear - 4.0 * l.quadratic * (l.constant - target);
            range = disc > 0 ? static_cast<float>((-l.linear + std::sqrt(disc)) / (2.0 * l.quadratic)) : 0.0f;
        } else if (l.linear > 0) {
            range = static_cast<float>((target - l.constant) / l.linear);
        }
    } else {
        range = 0;
    }
    range = std::clamp(range, 0.0f, 2048.0f);
    if (l.cutoff > 0) range = std::min(range, l.cutoff);
    return range;
}

struct LightTextures {
    Texture2D lights{};
    Texture2D grid{};
    int gridW = 1, gridH = 1;
    float originX = 0, originY = 0, cellSize = 640;
    size_t count = 0;
    size_t overflowCells = 0;
    size_t coveredCells = 0;
};

LightTextures BuildLightTextures(const Scene& scene) {
    LightTextures out;
    const auto& lights = scene.lights;
    out.count = lights.size();
    const int rows = std::max(1, static_cast<int>((lights.size() + kLightsPerRow - 1) / kLightsPerRow));
    std::vector<float> records(static_cast<size_t>(kLightsPerRow) * 5 * rows * 4, 0.0f);
    for (size_t i = 0; i < lights.size(); ++i) {
        const LightDef& l = lights[i];
        float* r = &records[((i / kLightsPerRow) * kLightsPerRow * 5 + (i % kLightsPerRow) * 5) * 4];
        const float v[20] = {l.position[0], l.position[1], l.position[2], l.type == LightType::Spot ? 1.0f : 0.0f,
                             l.color[0], l.color[1], l.color[2], l.cutoff,
                             l.direction[0], l.direction[1], l.direction[2], l.exponent,
                             l.constant, l.linear, l.quadratic, 0,
                             l.cosInner, l.cosOuter, 0, 0};
        std::memcpy(r, v, sizeof(v));
    }
    out.lights = FloatTexture(records, kLightsPerRow * 5, rows);

    const float margin = out.cellSize;
    out.originX = static_cast<float>(-scene.pitch * 0.5) - margin;
    out.originY = static_cast<float>(-(scene.gridHeight - 0.5) * scene.pitch) - margin;
    out.gridW = static_cast<int>(std::ceil((scene.gridWidth * scene.pitch + margin * 2) / out.cellSize));
    out.gridH = static_cast<int>(std::ceil((scene.gridHeight * scene.pitch + margin * 2) / out.cellSize));
    std::vector<std::vector<std::pair<float, int>>> candidates(static_cast<size_t>(out.gridW) * out.gridH);
    for (size_t i = 0; i < lights.size(); ++i) {
        const LightDef& l = lights[i];
        const float range = LightRange(l);
        if (range <= 0) continue;
        const float intensity = std::max({l.color[0], l.color[1], l.color[2]});
        const int x0 = std::max(0, static_cast<int>(std::floor((l.position[0] - range - out.originX) / out.cellSize)));
        const int x1 = std::min(out.gridW - 1, static_cast<int>(std::floor((l.position[0] + range - out.originX) / out.cellSize)));
        const int y0 = std::max(0, static_cast<int>(std::floor((l.position[1] - range - out.originY) / out.cellSize)));
        const int y1 = std::min(out.gridH - 1, static_cast<int>(std::floor((l.position[1] + range - out.originY) / out.cellSize)));
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const float cx0 = out.originX + x * out.cellSize, cy0 = out.originY + y * out.cellSize;
                const float nx = std::clamp(l.position[0], cx0, cx0 + out.cellSize);
                const float ny = std::clamp(l.position[1], cy0, cy0 + out.cellSize);
                const float dx = l.position[0] - nx, dy = l.position[1] - ny;
                const float d = std::sqrt(dx * dx + dy * dy);
                if (d > range) continue;
                const float score = intensity / std::max(1e-4f, l.constant + l.linear * d + l.quadratic * d * d);
                candidates[static_cast<size_t>(y) * out.gridW + x].push_back({score, static_cast<int>(i)});
            }
        }
    }
    std::vector<float> grid(static_cast<size_t>(out.gridW) * 2 * out.gridH * 4, -1.0f);
    for (int y = 0; y < out.gridH; ++y) {
        for (int x = 0; x < out.gridW; ++x) {
            auto& list = candidates[static_cast<size_t>(y) * out.gridW + x];
            if (list.empty()) continue;
            ++out.coveredCells;
            if (list.size() > kLightsPerCell) {
                ++out.overflowCells;
                std::partial_sort(list.begin(), list.begin() + kLightsPerCell, list.end(),
                                  [](const auto& a, const auto& b) { return a.first > b.first; });
                list.resize(kLightsPerCell);
            }
            float* cell = &grid[(static_cast<size_t>(y) * out.gridW * 2 + x * 2) * 4];
            for (size_t k = 0; k < list.size(); ++k) cell[k] = static_cast<float>(list[k].second);
        }
    }
    out.grid = FloatTexture(grid, out.gridW * 2, out.gridH);
    return out;
}

Color HashColor(const std::string& s) {
    const uint64_t h = Fnv1a(s);
    return Color{static_cast<unsigned char>(70 + (h & 0x9F)), static_cast<unsigned char>(70 + ((h >> 8) & 0x9F)),
                 static_cast<unsigned char>(70 + ((h >> 16) & 0x9F)), 255};
}

Color ToColor(Rgb c) { return Color{c.r, c.g, c.b, 255}; }

enum class MapMode { District = 1, Environment, Density, Landmark, Radiation };

const char* ModeName(MapMode m) {
    switch (m) {
        case MapMode::District: return "district";
        case MapMode::Environment: return "environment";
        case MapMode::Density: return "building density";
        case MapMode::Landmark: return "landmarks";
        case MapMode::Radiation: return "radiation";
    }
    return "";
}

struct FlyCamera {
    Vector3 pos{0, 0, 0};
    float yaw = 0, pitch = -0.6f;
    float speed = 3000;
    Vector3 Forward() const {
        return {std::cos(pitch) * std::cos(yaw), std::cos(pitch) * std::sin(yaw), std::sin(pitch)};
    }
    Camera3D ToCamera() const {
        Camera3D c{};
        c.position = pos;
        c.target = Vector3Add(pos, Forward());
        c.up = {0, 0, 1};
        c.fovy = 70;
        c.projection = CAMERA_PERSPECTIVE;
        return c;
    }
    void LookAtCell(const Scene& scene, int x, int y) {
        double wx, wy;
        scene.CellCenter(x, y, wx, wy);
        pos = {static_cast<float>(wx) - 4200, static_cast<float>(wy) - 4200, 5200};
        yaw = 0.785398f;
        pitch = -0.62f;
    }
    void Overview(const Scene& scene) {
        const float w = static_cast<float>(scene.gridWidth * scene.pitch);
        const float h = static_cast<float>(scene.gridHeight * scene.pitch);
        pos = {w * 0.5f, -h * 1.05f, w * 0.55f};
        yaw = 1.5708f;
        pitch = -0.75f;
    }
};

std::string Join(const std::vector<std::string>& parts, const char* sep) {
    std::string out;
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i) out += sep;
        out += parts[i];
    }
    return out;
}

// --- Cell/tile inspector ----------------------------------------------------------------------
// A cell spans 9x9 tile slots of 640 units (core 5x5, border ring, outer ring), centred on the cell.
constexpr int kSlots = 9;
constexpr float kTile = 640.0f;
constexpr float kHalfArea = kTile * kSlots * 0.5f;

int SlotIndex(float local) { return static_cast<int>(std::floor((local + kHalfArea) / kTile)); }

bool IsInfill(const TileRef& t) { return t.relative.find("infill") != std::string::npos; }

bool IsCoordinateToken(const std::string& s) {
    if (s.empty()) return false;
    if (s == "N" || s == "E" || s == "S" || s == "W" || s == "NE" || s == "NW" || s == "SE" || s == "SW") return true;
    size_t i = (s[0] == '-') ? 1 : 0;
    if (i >= s.size()) return false;
    for (; i < s.size(); ++i)
        if (s[i] < '0' || s[i] > '9') return false;
    return true;
}

// Role from the placement targetname (zm_tile_decoration_1_2 -> tile_decoration, zm_border_N_0_-1 -> border).
std::string TileRole(const TileRef& t) {
    std::string name = t.targetname;
    if (name.rfind("zm_", 0) == 0) name = name.substr(3);
    std::vector<std::string> tokens;
    size_t start = 0;
    while (start <= name.size()) {
        const size_t end = name.find('_', start);
        tokens.push_back(name.substr(start, end == std::string::npos ? std::string::npos : end - start));
        if (end == std::string::npos) break;
        start = end + 1;
    }
    while (!tokens.empty() && IsCoordinateToken(tokens.back())) tokens.pop_back();
    if (tokens.empty() || tokens.front().empty()) return fs::path(t.relative).parent_path().filename().string();
    return Join(tokens, "_");
}

std::string ReplaceFirst(std::string s, const std::string& from, const std::string& to) {
    const size_t at = s.find(from);
    if (at != std::string::npos) s.replace(at, from.size(), to);
    return s;
}

std::string TileLabel(const TileRef& t) {
    std::string stem = fs::path(t.relative).stem().string();
    if (stem.rfind("tile_", 0) == 0) stem = stem.substr(5);
    stem = ReplaceFirst(stem, "skyscraper_", "sky_");
    stem = ReplaceFirst(stem, "building_", "b_");
    stem = ReplaceFirst(stem, "border_", "bd_");
    stem = ReplaceFirst(stem, "motorway_", "mw_");
    return stem;
}

struct CellSlots {
    int cell = -1;
    std::array<std::vector<int>, kSlots * kSlots> tiles;  // per slot, most relevant first
};

CellSlots BuildSlots(const CellInfo& c, int cellIndex) {
    CellSlots out;
    out.cell = cellIndex;
    std::array<std::vector<std::pair<int, int>>, kSlots * kSlots> ranked;
    for (size_t i = 0; i < c.tiles.size(); ++i) {
        const TileRef& t = c.tiles[i];
        const int ox = SlotIndex(t.origin[0]), oy = SlotIndex(-t.origin[1]);
        int x0 = ox, x1 = ox, y0 = oy, y1 = oy;
        if (t.hasBounds) {
            // Shrink slightly so authored overhangs do not claim neighbouring slots.
            const float m = 96.0f;
            const int bx0 = SlotIndex(t.minX + m), bx1 = SlotIndex(t.maxX - m);
            const int by0 = SlotIndex(-(t.maxY - m)), by1 = SlotIndex(-(t.minY + m));
            if (bx0 <= bx1 && by0 <= by1 && bx1 - bx0 < kSlots && by1 - by0 < kSlots) {
                x0 = std::min(bx0, ox); x1 = std::max(bx1, ox);
                y0 = std::min(by0, oy); y1 = std::max(by1, oy);
            }
        }
        x0 = std::max(x0, 0); y0 = std::max(y0, 0);
        x1 = std::min(x1, kSlots - 1); y1 = std::min(y1, kSlots - 1);
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const int rank = (IsInfill(t) ? 2 : 0) + ((x == ox && y == oy) ? 0 : 1);
                ranked[y * kSlots + x].push_back({rank, static_cast<int>(i)});
            }
        }
    }
    for (size_t s = 0; s < ranked.size(); ++s) {
        std::stable_sort(ranked[s].begin(), ranked[s].end(), [](const auto& a, const auto& b) { return a.first < b.first; });
        for (const auto& [rank, index] : ranked[s]) out.tiles[s].push_back(index);
    }
    return out;
}

struct InspectorLayout {
    Rectangle panel{}, close{}, recipe{}, grid{};
    float slotPx = 40;
    bool popup = false;
    Rectangle popupRect{}, popupClose{};
    std::vector<std::pair<Rectangle, int>> open;  // Open-in-Hammer buttons and their tile index
    int hiddenEntries = 0;
};

constexpr int kPopupEntries = 7;
constexpr int kEntryHeight = 64;

InspectorLayout LayoutInspector(const CellSlots& slots, int slotX, int slotY, float top) {
    InspectorLayout l;
    l.panel = {8, top, 16 + l.slotPx * kSlots, 64 + l.slotPx * kSlots};
    l.close = {l.panel.x + l.panel.width - 26, l.panel.y + 6, 20, 20};
    l.recipe = {l.panel.x + 8, l.panel.y + 28, 170, 20};
    l.grid = {l.panel.x + 8, l.panel.y + 56, l.slotPx * kSlots, l.slotPx * kSlots};
    if (slotX >= 0 && slotY >= 0) {
        const auto& list = slots.tiles[slotY * kSlots + slotX];
        const int shown = std::min(static_cast<int>(list.size()), kPopupEntries);
        l.hiddenEntries = static_cast<int>(list.size()) - shown;
        l.popup = true;
        l.popupRect = {l.panel.x + l.panel.width + 8, top, 640,
                       static_cast<float>(40 + std::max(1, shown) * kEntryHeight + (l.hiddenEntries ? 16 : 0))};
        l.popupClose = {l.popupRect.x + l.popupRect.width - 26, l.popupRect.y + 6, 20, 20};
        for (int i = 0; i < shown; ++i)
            l.open.push_back({Rectangle{l.popupRect.x + l.popupRect.width - 136, l.popupRect.y + 36 + i * kEntryHeight, 124, 20},
                              list[i]});
    }
    return l;
}

void DrawButton(const Rectangle& r, const char* text, const Vector2& mouse) {
    const bool hot = CheckCollisionPointRec(mouse, r);
    DrawRectangleRec(r, hot ? Color{90, 110, 150, 255} : Color{55, 65, 85, 255});
    DrawRectangleLinesEx(r, 1, Color{150, 165, 190, 255});
    const int w = MeasureText(text, 10);
    DrawText(text, static_cast<int>(r.x + (r.width - w) / 2), static_cast<int>(r.y + (r.height - 10) / 2), 10, RAYWHITE);
}

// Longest prefix of text that fits in width pixels at font size 10.
std::string FitText(const std::string& text, float width) {
    std::string s = text;
    while (!s.empty() && MeasureText(s.c_str(), 10) > width) s.pop_back();
    return s;
}

}  // namespace

int main(int argc, char** argv) {
    Options options;
    if (!ParseArgs(argc, argv, options)) {
        std::fprintf(stderr,
                     "usage: zombiesim-world-viewer --plan <plan.json> [--repo <zombiesim root>] [--cell x y [--street] | --overview]\n"
                     "       [--screenshot out.png --frames N] [--size w h] [--stats] [--untextured] [--lit] [--night] [--props]\n"
                     "       [--hammer <hammer exe>] [--inspect x y] [--model <models/x.mdl>]...\n");
        return 2;
    }
    if (options.repo.empty()) options.repo = fs::current_path();
    options.repo = fs::absolute(options.repo).lexically_normal();
    if (!options.plan.empty() && options.plan.is_relative()) options.plan = (options.repo / options.plan).lexically_normal();

    fs::path garrysmod = (options.repo / ".." / "..").lexically_normal();
    if (!garrysmod.has_filename()) garrysmod = garrysmod.parent_path();  // drop the trailing separator
    const fs::path gmodRoot = garrysmod.parent_path();
    GameFileSystem files;
    files.AddLooseRoot(options.repo / "content");
    files.AddLooseRoot(garrysmod);
    for (const fs::path vpk : {garrysmod / "garrysmod_dir.vpk", garrysmod / "fallbacks_dir.vpk",
                                gmodRoot / "sourceengine" / "content_cstrike_dir.vpk",
                                gmodRoot / "sourceengine" / "content_hl2_dir.vpk",
                                gmodRoot / "sourceengine" / "hl2_misc_dir.vpk",
                                gmodRoot / "sourceengine" / "hl2_textures_dir.vpk"}) {
        if (fs::exists(vpk)) files.AddVpk(vpk);
    }
    MaterialColors colors(files);

    if (!options.models.empty()) {
        int failures = 0;
        for (const std::string& model : options.models) {
            StudioLoadResult result;
            if (!LoadStudioModel(files, colors, model, 0, result)) {
                std::printf("%s: FAILED %s\n", model.c_str(), result.error.c_str());
                ++failures;
                continue;
            }
            const auto& lo = result.mesh.boundsMin;
            const auto& hi = result.mesh.boundsMax;
            std::printf("%s: %zu triangles, %s\n  bounds (%.1f %.1f %.1f) .. (%.1f %.1f %.1f)\n", model.c_str(),
                        result.mesh.TriangleCount(), result.poseInfo.c_str(), lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]);
        }
        return failures ? 1 : 0;
    }
    Scene scene;
    std::string error;
    std::printf("Loading %s\n", options.plan.string().c_str());
    if (!scene.Load(options.plan, options.repo, colors, error)) {
        std::fprintf(stderr, "error: %s\n", error.c_str());
        return 1;
    }
    const SceneStats& st = scene.stats;
    int missingRecipes = 0;
    for (const auto& c : scene.cells) missingRecipes += c.recipeMissing ? 1 : 0;
    std::printf("cells %zu (%dx%d), models %zu, instances %zu, draw items %zu, triangles %zu\n", scene.cells.size(),
                scene.gridWidth, scene.gridHeight, st.models, st.instances, scene.items.size(), st.triangles);
    std::printf("brushes %zu, displacements %zu, failed sides %zu, depth-limited %zu\n", st.brushes, st.displacements,
                st.failedSides, st.depthLimited);
    std::printf("props: %zu entities, %zu placed, %zu failed, %zu studio meshes, %zu triangles\n", st.props,
                st.propInstances, st.failedProps, st.studioModels, st.propTriangles);
    for (size_t i = 0; i < scene.failedStudioModels.size() && i < 20; ++i)
        std::printf("  prop model: %s\n", scene.failedStudioModels[i].c_str());
    for (const auto& d : files.Describe()) std::printf("mount: %s\n", d.c_str());
    std::printf("materials: %zu from textures, %zu from keywords, %zu total, %zu texture tiles, %zu texture failures\n",
                colors.ResolvedFromTextures(), colors.ResolvedFromKeywords(), colors.Materials(), colors.Tiles().size(),
                colors.TextureFailures());
    std::printf("lights: %zu point/spot, %zu light_environment (sun %s)\n", scene.lights.size(),
                st.environmentLights, scene.hasSun ? "found" : "missing");
    if (!scene.lights.empty()) {
        std::map<std::pair<int, int>, int> perCell;
        for (const auto& l : scene.lights) {
            const int cx = static_cast<int>(std::floor(l.position[0] / scene.pitch + 0.5));
            const int cy = static_cast<int>(std::floor(-l.position[1] / scene.pitch + 0.5));
            ++perCell[{cx, cy}];
        }
        auto best = std::max_element(perCell.begin(), perCell.end(),
                                     [](const auto& a, const auto& b) { return a.second < b.second; });
        std::printf("lit cells %zu, most lights %d at cell %d %d\n", perCell.size(), best->second,
                    best->first.first, best->first.second);
    }
    std::printf("missing recipes %d, missing files %zu, provenance %s, load %.1fs\n", missingRecipes,
                st.missingFiles, scene.provenance.c_str(), st.loadSeconds);
    for (size_t i = 0; i < scene.missingFiles.size() && i < 20; ++i)
        std::printf("  missing: %s\n", scene.missingFiles[i].c_str());
    int failedModels = 0;
    for (const auto& m : scene.models) {
        if (!m.loaded) {
            if (failedModels < 10) std::printf("  load error: %s\n", m.error.c_str());
            ++failedModels;
        }
    }
    if (options.noWindow) return (missingRecipes || st.missingFiles || failedModels) ? 1 : 0;

    // Aggregate per-district statistics for the Tab table.
    struct DistrictRow {
        int cells = 0;
        int buildings = 0;
        std::map<std::string, int> categories;
        std::map<std::string, int> landmarks;
    };
    std::map<std::string, DistrictRow> districtRows;
    for (const auto& c : scene.cells) {
        DistrictRow& row = districtRows[c.district.empty() ? "(none)" : c.district];
        ++row.cells;
        for (const auto& [k, v] : c.buildingCategories) {
            row.categories[k] += v;
            row.buildings += v;
        }
        for (const auto& l : c.landmarks) ++row.landmarks[l.name];
    }
    std::unordered_map<std::string, Rgb> districtColor;
    for (const auto& d : scene.districts) districtColor[d.name] = d.color;

    SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(options.width, options.height, "ZombieSim world viewer");
    SetTargetFPS(144);

    Shader shader = LoadShaderFromMemory(kVertexShader, kFragmentShader);
    shader.locs[SHADER_LOC_MATRIX_MVP] = GetShaderLocation(shader, "mvp");
    shader.locs[SHADER_LOC_MATRIX_MODEL] = GetShaderLocationAttrib(shader, "instanceTransform");
    const int locViewPos = GetShaderLocation(shader, "viewPos");
    const int locSun = GetShaderLocation(shader, "sunDir");
    const int locFogColor = GetShaderLocation(shader, "fogColor");
    const int locFogDensity = GetShaderLocation(shader, "fogDensity");
    const int locTint = GetShaderLocation(shader, "tint");
    const int locTextured = GetShaderLocation(shader, "textured");
    const int locLit = GetShaderLocation(shader, "lit");
    const int locAtlas = GetShaderLocation(shader, "atlas");
    const int locAtlasSize = GetShaderLocation(shader, "atlasSize");
    const int locSunColor = GetShaderLocation(shader, "sunColor");
    const int locAmbient = GetShaderLocation(shader, "ambientColor");
    const int locLightGrid = GetShaderLocation(shader, "lightGrid");
    const int locLightGridSize = GetShaderLocation(shader, "lightGridSize");
    shader.locs[SHADER_LOC_VERTEX_TEXCOORD01] = GetShaderLocationAttrib(shader, "vertexTexCoord");
    shader.locs[SHADER_LOC_VERTEX_TEXCOORD02] = GetShaderLocationAttrib(shader, "vertexTexCoord2");
    shader.locs[SHADER_LOC_MAP_ALBEDO] = GetShaderLocation(shader, "texture0");
    shader.locs[SHADER_LOC_MAP_METALNESS] = GetShaderLocation(shader, "texture1");
    shader.locs[SHADER_LOC_MAP_NORMAL] = GetShaderLocation(shader, "texture2");
    Material material = LoadMaterialDefault();
    material.shader = shader;

    const Atlas atlas = BuildAtlas(colors.Tiles());
    const LightTextures lightTex = BuildLightTextures(scene);
    material.maps[MATERIAL_MAP_ALBEDO].texture = atlas.texture;
    material.maps[MATERIAL_MAP_METALNESS].texture = lightTex.lights;
    material.maps[MATERIAL_MAP_NORMAL].texture = lightTex.grid;
    {
        const float atlasInfo[4] = {static_cast<float>(atlas.columns), static_cast<float>(atlas.cell),
                                    static_cast<float>(atlas.gutter), static_cast<float>(atlas.tile)};
        const float atlasSize[2] = {static_cast<float>(atlas.width), static_cast<float>(atlas.height)};
        const float grid[4] = {lightTex.originX, lightTex.originY, lightTex.cellSize, static_cast<float>(lightTex.count)};
        const int gridSize[2] = {lightTex.gridW, lightTex.gridH};
        SetShaderValue(shader, locAtlas, atlasInfo, SHADER_UNIFORM_VEC4);
        SetShaderValue(shader, locAtlasSize, atlasSize, SHADER_UNIFORM_VEC2);
        SetShaderValue(shader, locLightGrid, grid, SHADER_UNIFORM_VEC4);
        SetShaderValue(shader, locLightGridSize, gridSize, SHADER_UNIFORM_IVEC2);
    }
    std::printf("atlas %dx%d (%d px tiles), light grid %dx%d, %zu covered cells, %zu over %d lights\n", atlas.width,
                atlas.height, atlas.tile, lightTex.gridW, lightTex.gridH, lightTex.coveredCells, lightTex.overflowCells,
                kLightsPerCell);

    std::vector<Mesh> meshes(scene.models.size() * 2);
    std::vector<bool> hasMesh(meshes.size(), false);
    for (size_t i = 0; i < scene.models.size(); ++i) {
        if (scene.models[i].mesh.TriangleCount()) { meshes[i * 2] = Upload(scene.models[i].mesh); hasMesh[i * 2] = true; }
        if (scene.models[i].shell.TriangleCount()) { meshes[i * 2 + 1] = Upload(scene.models[i].shell); hasMesh[i * 2 + 1] = true; }
    }
    std::vector<Matrix> itemMatrices(scene.items.size());
    for (size_t i = 0; i < scene.items.size(); ++i) itemMatrices[i] = ToRay(scene.items[i].world);

    FlyCamera fly;
    int selected = -1;
    if (options.cellX >= 0) {
        fly.LookAtCell(scene, options.cellX, options.cellY);
        if (options.street) {
            // Low view down the cell's centre road for lighting checks.
            double wx, wy;
            scene.CellCenter(options.cellX, options.cellY, wx, wy);
            fly.pos = {static_cast<float>(wx), static_cast<float>(wy) - 1500, 220};
            fly.yaw = 1.5708f;
            fly.pitch = -0.12f;
        }
        selected = scene.CellIndexAt(options.cellX, options.cellY);
    } else {
        fly.Overview(scene);
    }

    bool showGrid = true, showShell = true, fog = true, showTable = false, showHelp = true;
    bool showProps = options.props;
    float propDistance = 12000;
    bool inOverview = options.cellX < 0, savedFree = false;
    Vector3 savedPos{};
    float savedYaw = 0, savedPitch = 0;
    MapMode mode = MapMode::District;
    float drawDistance = 160000;
    std::vector<std::vector<Matrix>> batches(meshes.size());
    int frame = 0;
    bool textured = options.textured, lit = options.lit, night = options.night;
    // The shader wants the direction toward the sun; the VMF gives the direction the light travels.
    const Vector3 sun = scene.hasSun
        ? Vector3Normalize({-scene.sun.direction[0], -scene.sun.direction[1], -scene.sun.direction[2]})
        : Vector3Normalize({0.45f, 0.3f, 0.84f});
    const Vector3 daySun = scene.hasSun ? Vector3{scene.sun.color[0], scene.sun.color[1], scene.sun.color[2]}
                                        : Vector3{1.6f, 1.5f, 1.3f};
    const Vector3 dayAmbient = scene.hasSun ? Vector3{scene.sun.ambient[0], scene.sun.ambient[1], scene.sun.ambient[2]}
                                            : Vector3{0.35f, 0.38f, 0.45f};

    // Tile inspector state.
    fs::path hammerExe = options.hammer;
    if (hammerExe.empty()) {
        hammerExe = gmodRoot / "bin" / "win64" / "hammerplusplus.exe";
        if (!fs::exists(hammerExe)) hammerExe = gmodRoot / "bin" / "hammer.exe";
    }
    int inspected = -1, slotX = -1, slotY = -1;
    CellSlots slots;
    int lastClickCell = -1;
    double lastClickTime = -10;
    std::string status;
    double statusUntil = 0;
    auto openInspector = [&](int index) {
        inspected = index;
        slots = BuildSlots(scene.cells[index], index);
        slotX = slotY = -1;
        selected = index;
    };
    auto noteCellClick = [&](int index) {
        const double now = GetTime();
        if (index >= 0 && index == lastClickCell && now - lastClickTime < 0.35) {
            openInspector(index);
            lastClickCell = -1;
            return;
        }
        lastClickCell = index;
        lastClickTime = now;
    };
    auto openFile = [&](const fs::path& file) {
        std::string err;
        if (OpenInHammer(hammerExe, file, err)) status = "Opening in Hammer: " + file.filename().string();
        else status = "Hammer failed: " + err;
        std::printf("%s\n", status.c_str());
        statusUntil = GetTime() + 6;
    };
    if (options.inspectX >= 0) {
        const int index = scene.CellIndexAt(options.inspectX, options.inspectY);
        if (index >= 0) {
            openInspector(index);
            fly.LookAtCell(scene, options.inspectX, options.inspectY);
            inOverview = false;
            slotX = slotY = kSlots / 2;
        }
    }
    SetExitKey(KEY_NULL);
    bool quit = false;

    while (!WindowShouldClose() && !quit) {
        const float dt = GetFrameTime();
        const int sw = GetScreenWidth(), sh = GetScreenHeight();
        const int cellPx = std::max(4, std::min(14, (sh - 40) / 2 / std::max(1, scene.gridHeight)));
        const Rectangle mapRect{static_cast<float>(sw - scene.gridWidth * cellPx - 12), 12.0f,
                                static_cast<float>(scene.gridWidth * cellPx), static_cast<float>(scene.gridHeight * cellPx)};
        const Vector2 mouse = GetMousePosition();
        const bool overMap = CheckCollisionPointRec(mouse, mapRect);
        if (IsKeyPressed(KEY_ESCAPE)) {
            if (slotX >= 0) slotX = slotY = -1;
            else if (inspected >= 0) inspected = -1;
            else quit = true;
        }
        const float inspectorTop = showHelp ? 172.0f : 78.0f;
        InspectorLayout ui = inspected >= 0 ? LayoutInspector(slots, slotX, slotY, inspectorTop) : InspectorLayout{};
        const bool overUi = inspected >= 0 &&
                            (CheckCollisionPointRec(mouse, ui.panel) || (ui.popup && CheckCollisionPointRec(mouse, ui.popupRect)));

        // Input.
        if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
            const Vector2 d = GetMouseDelta();
            fly.yaw -= d.x * 0.004f;
            fly.pitch = std::clamp(fly.pitch - d.y * 0.004f, -1.55f, 1.55f);
        }
        const Vector3 fwd = fly.Forward();
        const Vector3 right = Vector3Normalize({std::sin(fly.yaw), -std::cos(fly.yaw), 0});
        float speedScale = 1.0f;
        if (IsKeyDown(KEY_LEFT_SHIFT) || IsKeyDown(KEY_RIGHT_SHIFT)) speedScale *= 5.0f;
        if (IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT)) speedScale *= 0.2f;
        float speed = fly.speed * speedScale * dt;
        if (IsKeyDown(KEY_W)) fly.pos = Vector3Add(fly.pos, Vector3Scale(fwd, speed));
        if (IsKeyDown(KEY_S)) fly.pos = Vector3Subtract(fly.pos, Vector3Scale(fwd, speed));
        if (IsKeyDown(KEY_D)) fly.pos = Vector3Add(fly.pos, Vector3Scale(right, speed));
        if (IsKeyDown(KEY_A)) fly.pos = Vector3Subtract(fly.pos, Vector3Scale(right, speed));
        if (IsKeyDown(KEY_E)) fly.pos.z += speed;
        if (IsKeyDown(KEY_Q)) fly.pos.z -= speed;
        if (IsMouseButtonDown(MOUSE_BUTTON_MIDDLE)) {
            const Vector2 d = GetMouseDelta();
            const float k = std::max(1.0f, std::fabs(fly.pos.z)) * 0.0015f;
            fly.pos = Vector3Add(fly.pos, Vector3Scale(right, -d.x * k));
            fly.pos = Vector3Add(fly.pos, Vector3Scale(Vector3Normalize({std::cos(fly.yaw), std::sin(fly.yaw), 0}), d.y * k));
        }
        const float wheel = GetMouseWheelMove();
        if (wheel != 0) fly.speed = std::clamp(fly.speed * std::pow(1.25f, wheel), 100.0f, 200000.0f);
        if (IsKeyPressed(KEY_G)) showGrid = !showGrid;
        if (IsKeyPressed(KEY_B)) showShell = !showShell;
        if (IsKeyPressed(KEY_F)) fog = !fog;
        if (IsKeyPressed(KEY_TAB)) showTable = !showTable;
        if (IsKeyPressed(KEY_H)) showHelp = !showHelp;
        if (IsKeyPressed(KEY_O)) {
            // Toggle between the city overview and the last free-camera pose.
            if (inOverview && savedFree) {
                fly.pos = savedPos;
                fly.yaw = savedYaw;
                fly.pitch = savedPitch;
                inOverview = false;
            } else {
                savedPos = fly.pos;
                savedYaw = fly.yaw;
                savedPitch = fly.pitch;
                savedFree = true;
                fly.Overview(scene);
                inOverview = true;
            }
        }
        if (IsKeyPressed(KEY_C)) {
            const int focus = inspected >= 0 ? inspected : selected;
            if (focus >= 0) {
                fly.LookAtCell(scene, scene.cells[focus].x, scene.cells[focus].y);
                inOverview = false;
            }
        }
        if (IsKeyPressed(KEY_P)) showProps = !showProps;
        if (IsKeyPressed(KEY_LEFT_BRACKET)) propDistance = std::max(1000.0f, propDistance / 1.25f);
        if (IsKeyPressed(KEY_RIGHT_BRACKET)) propDistance *= 1.25f;
        if (IsKeyPressed(KEY_T)) textured = !textured;
        if (IsKeyPressed(KEY_L)) lit = !lit;
        if (IsKeyPressed(KEY_N)) { night = !night; if (night) lit = true; }
        if (IsKeyPressed(KEY_EQUAL)) drawDistance *= 1.25f;
        if (IsKeyPressed(KEY_MINUS)) drawDistance = std::max(10000.0f, drawDistance / 1.25f);
        for (int k = 1; k <= 5; ++k)
            if (IsKeyPressed(KEY_ZERO + k)) mode = static_cast<MapMode>(k);

        Camera3D camera = fly.ToCamera();
        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
            if (overUi) {
                if (CheckCollisionPointRec(mouse, ui.close)) {
                    inspected = -1;
                    slotX = slotY = -1;
                } else if (CheckCollisionPointRec(mouse, ui.recipe)) {
                    openFile(scene.cells[inspected].recipePath);
                } else if (CheckCollisionPointRec(mouse, ui.grid)) {
                    slotX = std::clamp(static_cast<int>((mouse.x - ui.grid.x) / ui.slotPx), 0, kSlots - 1);
                    slotY = std::clamp(static_cast<int>((mouse.y - ui.grid.y) / ui.slotPx), 0, kSlots - 1);
                } else if (ui.popup && CheckCollisionPointRec(mouse, ui.popupClose)) {
                    slotX = slotY = -1;
                } else {
                    for (const auto& [rect, tile] : ui.open)
                        if (CheckCollisionPointRec(mouse, rect)) openFile(scene.cells[inspected].tiles[tile].file);
                }
            } else if (overMap) {
                const int gx = static_cast<int>((mouse.x - mapRect.x) / cellPx);
                const int gy = static_cast<int>((mouse.y - mapRect.y) / cellPx);
                selected = scene.CellIndexAt(gx, gy);
                noteCellClick(selected);
            } else {
                const Ray ray = GetScreenToWorldRay(mouse, camera);
                if (std::fabs(ray.direction.z) > 1e-4f) {
                    const float t = (32.0f - ray.position.z) / ray.direction.z;
                    if (t > 0) {
                        const Vector3 p = Vector3Add(ray.position, Vector3Scale(ray.direction, t));
                        bool slotPicked = false;
                        if (inspected >= 0) {
                            double wx, wy;
                            scene.CellCenter(scene.cells[inspected].x, scene.cells[inspected].y, wx, wy);
                            const float lx = p.x - static_cast<float>(wx), ly = p.y - static_cast<float>(wy);
                            if (std::fabs(lx) < kHalfArea && std::fabs(ly) < kHalfArea) {
                                slotX = std::clamp(SlotIndex(lx), 0, kSlots - 1);
                                slotY = std::clamp(SlotIndex(-ly), 0, kSlots - 1);
                                slotPicked = true;
                            }
                        }
                        if (!slotPicked) {
                            const int gx = static_cast<int>(std::lround(p.x / scene.pitch));
                            const int gy = static_cast<int>(std::lround(-p.y / scene.pitch));
                            selected = scene.CellIndexAt(gx, gy);
                            noteCellClick(selected);
                        }
                    }
                }
            }
        }
        camera = fly.ToCamera();

        // Cull and batch.
        for (auto& b : batches) b.clear();
        const float cosLimit = std::cos(DEG2RAD * 75.0f);
        size_t drawnTriangles = 0;
        for (size_t i = 0; i < scene.items.size(); ++i) {
            const DrawItem& it = scene.items[i];
            if (it.shell && !showShell) continue;
            if (it.prop && !showProps) continue;
            const Vector3 v{it.center[0] - fly.pos.x, it.center[1] - fly.pos.y, it.center[2] - fly.pos.z};
            const float dist = Vector3Length(v);
            // Props also fade out by apparent size so small clutter does not dominate the triangle budget.
            const float limit = it.prop ? std::min({drawDistance, propDistance, it.radius * 120.0f}) : drawDistance;
            if (dist - it.radius > limit) continue;
            if (dist > it.radius && Vector3DotProduct(v, fwd) < dist * cosLimit - it.radius) continue;
            const size_t slot = static_cast<size_t>(it.model) * 2 + (it.shell ? 1 : 0);
            batches[slot].push_back(itemMatrices[i]);
            drawnTriangles += (it.shell ? scene.models[it.model].shell : scene.models[it.model].mesh).TriangleCount();
        }

        // Fog reaches ~37% at the view distance so the far edge of the city stays readable.
        const float density = fog ? 1.0f / drawDistance : 0.0f;
        const float tintMesh = 1.0f, tintShell = 0.35f;
        const Vector3 fogColor = night ? Vector3{0.05f, 0.055f, 0.08f} : Vector3{0.62f, 0.66f, 0.70f};
        SetShaderValue(shader, locViewPos, &fly.pos, SHADER_UNIFORM_VEC3);
        SetShaderValue(shader, locSun, &sun, SHADER_UNIFORM_VEC3);
        SetShaderValue(shader, locFogColor, &fogColor, SHADER_UNIFORM_VEC3);
        SetShaderValue(shader, locFogDensity, &density, SHADER_UNIFORM_FLOAT);
        {
            const int texturedValue = textured ? 1 : 0, litValue = lit ? 1 : 0;
            const Vector3 sunColor = night ? Vector3{0, 0, 0} : daySun;
            const Vector3 ambient = night ? Vector3{0.015f, 0.017f, 0.025f} : dayAmbient;
            SetShaderValue(shader, locTextured, &texturedValue, SHADER_UNIFORM_INT);
            SetShaderValue(shader, locLit, &litValue, SHADER_UNIFORM_INT);
            SetShaderValue(shader, locSunColor, &sunColor, SHADER_UNIFORM_VEC3);
            SetShaderValue(shader, locAmbient, &ambient, SHADER_UNIFORM_VEC3);
        }

        BeginDrawing();
        ClearBackground(night ? Color{12, 14, 20, 255} : Color{158, 168, 178, 255});
        rlSetClipPlanes(16.0, 400000.0);
        BeginMode3D(camera);
        rlDisableBackfaceCulling();
        for (size_t slot = 0; slot < batches.size(); ++slot) {
            if (batches[slot].empty() || !hasMesh[slot]) continue;
            SetShaderValue(shader, locTint, (slot & 1) ? &tintShell : &tintMesh, SHADER_UNIFORM_FLOAT);
            DrawMeshInstanced(meshes[slot], material, batches[slot].data(), static_cast<int>(batches[slot].size()));
        }
        rlEnableBackfaceCulling();
        if (showGrid) {
            const float half = static_cast<float>(scene.pitch * 0.5);
            for (const auto& c : scene.cells) {
                double wx, wy;
                scene.CellCenter(c.x, c.y, wx, wy);
                const float x0 = static_cast<float>(wx) - half, x1 = static_cast<float>(wx) + half;
                const float y0 = static_cast<float>(wy) - half, y1 = static_cast<float>(wy) + half;
                const Color col = Color{255, 255, 255, 60};
                DrawLine3D({x0, y0, 80}, {x1, y0, 80}, col);
                DrawLine3D({x0, y0, 80}, {x0, y1, 80}, col);
                if (c.empty) {
                    DrawCube({static_cast<float>(wx), static_cast<float>(wy), 0}, half * 2, half * 2, 8, ToColor(c.emptyColor));
                }
            }
        }
        if (selected >= 0) {
            const CellInfo& c = scene.cells[selected];
            double wx, wy;
            scene.CellCenter(c.x, c.y, wx, wy);
            const float s = static_cast<float>(scene.visualHalfExtent * 2);
            DrawCubeWires({static_cast<float>(wx), static_cast<float>(wy), 600}, s, s, 1200, YELLOW);
        }
        if (inspected >= 0) {
            const CellInfo& c = scene.cells[inspected];
            double cwx, cwy;
            scene.CellCenter(c.x, c.y, cwx, cwy);
            const float wx = static_cast<float>(cwx), wy = static_cast<float>(cwy);
            for (int i = 0; i <= kSlots; ++i) {
                const float o = -kHalfArea + i * kTile;
                const bool core = i >= 2 && i <= 7;
                const Color col = core ? Color{120, 220, 255, 200} : Color{120, 220, 255, 90};
                DrawLine3D({wx + o, wy - kHalfArea, 90}, {wx + o, wy + kHalfArea, 90}, col);
                DrawLine3D({wx - kHalfArea, wy + o, 90}, {wx + kHalfArea, wy + o, 90}, col);
            }
            if (slotX >= 0) {
                const float sx = wx - kHalfArea + (slotX + 0.5f) * kTile;
                const float sy = wy + kHalfArea - (slotY + 0.5f) * kTile;
                DrawCubeWires({sx, sy, 400}, kTile, kTile, 800, SKYBLUE);
                const auto& list = slots.tiles[slotY * kSlots + slotX];
                if (!list.empty()) {
                    const TileRef& t = c.tiles[list.front()];
                    if (t.hasBounds)
                        DrawCubeWires({wx + (t.minX + t.maxX) * 0.5f, wy + (t.minY + t.maxY) * 0.5f, (t.minZ + t.maxZ) * 0.5f},
                                      t.maxX - t.minX, t.maxY - t.minY, std::max(8.0f, t.maxZ - t.minZ), ORANGE);
                }
            }
        }
        EndMode3D();

        // Minimap.
        DrawRectangle(static_cast<int>(mapRect.x) - 4, static_cast<int>(mapRect.y) - 4,
                      static_cast<int>(mapRect.width) + 8, static_cast<int>(mapRect.height) + 22, Color{0, 0, 0, 170});
        for (size_t i = 0; i < scene.cells.size(); ++i) {
            const CellInfo& c = scene.cells[i];
            Color col = DARKGRAY;
            switch (mode) {
                case MapMode::District: {
                    const auto it = districtColor.find(c.district);
                    col = it != districtColor.end() ? ToColor(it->second) : DARKGRAY;
                    break;
                }
                case MapMode::Environment: col = HashColor(c.environment); break;
                case MapMode::Density:
                    col = c.buildingTier >= 3 ? Color{220, 70, 60, 255}
                          : c.buildingTier == 2 ? Color{230, 190, 60, 255}
                          : c.buildingTier == 1 ? Color{90, 180, 90, 255} : Color{60, 60, 60, 255};
                    break;
                case MapMode::Landmark:
                    col = c.landmarks.empty() ? Color{45, 45, 45, 255} : ToColor(c.landmarks.front().color);
                    break;
                case MapMode::Radiation: {
                    const unsigned char r = static_cast<unsigned char>(std::clamp(c.radiation, 0.0, 1.0) * 255);
                    col = Color{static_cast<unsigned char>(30 + r / 2), static_cast<unsigned char>(40 + r * 3 / 4), 30, 255};
                    break;
                }
            }
            if (c.empty) col = ToColor(c.emptyColor);
            if (c.recipeMissing || c.missingInstances) col = MAGENTA;
            DrawRectangle(static_cast<int>(mapRect.x) + c.x * cellPx, static_cast<int>(mapRect.y) + c.y * cellPx,
                          cellPx - 1, cellPx - 1, col);
            if (c.safeZone) DrawRectangleLines(static_cast<int>(mapRect.x) + c.x * cellPx, static_cast<int>(mapRect.y) + c.y * cellPx,
                                              cellPx - 1, cellPx - 1, WHITE);
        }
        if (selected >= 0) {
            const CellInfo& c = scene.cells[selected];
            DrawRectangleLines(static_cast<int>(mapRect.x) + c.x * cellPx - 1, static_cast<int>(mapRect.y) + c.y * cellPx - 1,
                               cellPx + 1, cellPx + 1, YELLOW);
        }
        {
            const float cx = mapRect.x + static_cast<float>(fly.pos.x / scene.pitch + 0.5) * cellPx;
            const float cy = mapRect.y + static_cast<float>(-fly.pos.y / scene.pitch + 0.5) * cellPx;
            DrawCircleV({cx, cy}, 3, RED);
            DrawLineV({cx, cy}, {cx + std::cos(fly.yaw) * 10, cy - std::sin(fly.yaw) * 10}, RED);
        }
        DrawText(TextFormat("map: %s (1-5)", ModeName(mode)), static_cast<int>(mapRect.x),
                 static_cast<int>(mapRect.y + mapRect.height + 3), 10, RAYWHITE);

        // HUD.
        DrawRectangle(8, 8, 560, showHelp ? 158 : 62, Color{0, 0, 0, 160});
        DrawText(TextFormat("%s   provenance %s", options.plan.filename().string().c_str(), scene.provenance.c_str()), 16, 14, 10, RAYWHITE);
        DrawText(TextFormat("FPS %d   drawn tris %zu / %zu   items %zu   speed %.0f   view %.0f", GetFPS(), drawnTriangles,
                            st.triangles, scene.items.size(), fly.speed, drawDistance), 16, 28, 10, RAYWHITE);
        DrawText(TextFormat("missing recipes %d  missing files %zu  failed sides %zu  props %s (%zu placed, %zu failed)",
                            missingRecipes, st.missingFiles, st.failedSides, showProps ? "on" : "off", st.propInstances,
                            st.failedProps), 16, 42, 10,
                 (missingRecipes || st.missingFiles) ? Color{255, 120, 120, 255} : RAYWHITE);
        if (showHelp) {
            DrawText("WASD move, Q/E down/up, Shift fast, Alt slow, wheel speed, right-drag look, middle-drag pan", 16, 62, 10, LIGHTGRAY);
            DrawText("left click: select cell (3D or minimap)   C focus camera on cell   1-5 minimap mode   Tab district table", 16, 76, 10, LIGHTGRAY);
            DrawText("G grid   B black shell   F fog   O overview/back   +/- view distance   F12 screenshot   H help", 16, 90, 10, LIGHTGRAY);
            DrawText(TextFormat("T textures [%s]   L lit [%s]   N night [%s]   P props [%s, [/] range %.0f]   (%zu lights, sun %s)",
                                textured ? "on" : "off", lit ? "on" : "off", night ? "on" : "off", showProps ? "on" : "off",
                                propDistance, scene.lights.size(), scene.hasSun ? "from VMF" : "default"),
                     16, 104, 10, LIGHTGRAY);
            DrawText("Brushes, displacements and props from the exact recipe VMFs. Lit = VMF lights, no shadows/bounce.", 16, 120, 10, GRAY);
            DrawText("Magenta minimap cells have a missing recipe or instance file.", 16, 134, 10, GRAY);
            DrawText("Double-click a cell: tile inspector. Click a tile slot (panel or 3D) for its file + Open in Hammer. Esc closes.",
                     16, 148, 10, LIGHTGRAY);
        }

        if (selected >= 0) {
            const CellInfo& c = scene.cells[selected];
            std::vector<std::string> lines;
            lines.push_back(TextFormat("grid %d,%d   logical %d,%d", c.x, c.y, c.logicalX, c.logicalY));
            lines.push_back(c.empty ? std::string("EMPTY cell (no recipe)") : "recipe " + c.recipe);
            lines.push_back("topology " + c.topology + (c.orientation.empty() ? "" : " / " + c.orientation));
            lines.push_back("environment " + c.environment + "   district " + c.district);
            lines.push_back(TextFormat("density building %d scenery %d   radiation %.2f   danger %.2f", c.buildingTier,
                                       c.sceneryTier, c.radiation, c.danger));
            std::vector<std::string> lm;
            for (const auto& l : c.landmarks) lm.push_back(l.name);
            lines.push_back("landmarks " + (lm.empty() ? std::string("-") : Join(lm, ", ")) + (c.safeZone ? "   SAFE ZONE" : ""));
            lines.push_back(TextFormat("instances %zu   triangles %zu   missing instances %d", c.instanceCount,
                                       c.triangleCount, c.missingInstances));
            lines.push_back("buildings:");
            for (const auto& [k, v] : c.buildingCategories) lines.push_back(TextFormat("  %s x%d", k.c_str(), v));
            const int h = static_cast<int>(lines.size()) * 14 + 12;
            DrawRectangle(8, sh - h - 8, 520, h, Color{0, 0, 0, 170});
            for (size_t i = 0; i < lines.size(); ++i)
                DrawText(lines[i].c_str(), 16, sh - h - 2 + static_cast<int>(i) * 14, 10, RAYWHITE);
        }

        if (showTable) {
            const int rowH = 14;
            const int h = static_cast<int>(districtRows.size()) * rowH * 2 + 40;
            const int x0 = 300, y0 = 170;
            DrawRectangle(x0, y0, sw - x0 - 20, h, Color{0, 0, 0, 200});
            DrawText("District | cells | buildings | top building categories | landmarks", x0 + 8, y0 + 8, 10, YELLOW);
            int y = y0 + 26;
            for (const auto& [name, row] : districtRows) {
                std::vector<std::pair<int, std::string>> top;
                for (const auto& [k, v] : row.categories) top.push_back({-v, k});
                std::sort(top.begin(), top.end());
                std::string cats;
                for (size_t i = 0; i < top.size() && i < 9; ++i) cats += TextFormat("%s %d  ", top[i].second.c_str(), -top[i].first);
                std::string lms;
                for (const auto& [k, v] : row.landmarks) lms += TextFormat("%s %d  ", k.c_str(), v);
                DrawText(TextFormat("%s | %d | %d | %s", name.c_str(), row.cells, row.buildings, cats.c_str()), x0 + 8, y, 10, RAYWHITE);
                DrawText(TextFormat("      landmarks: %s", lms.empty() ? "-" : lms.c_str()), x0 + 8, y + rowH, 10, LIGHTGRAY);
                y += rowH * 2;
            }
        }

        if (inspected >= 0) {
            const CellInfo& c = scene.cells[inspected];
            DrawRectangleRec(ui.panel, Color{10, 14, 22, 225});
            DrawRectangleLinesEx(ui.panel, 1, Color{120, 220, 255, 180});
            DrawText(TextFormat("Cell %d,%d (logical %d,%d)  %zu tiles", c.x, c.y, c.logicalX, c.logicalY, c.tiles.size()),
                     static_cast<int>(ui.panel.x + 8), static_cast<int>(ui.panel.y + 8), 10, YELLOW);
            DrawButton(ui.close, "X", mouse);
            DrawButton(ui.recipe, "Open recipe in Hammer", mouse);
            DrawText(FitText(c.recipe, ui.panel.width - ui.recipe.width - 28).c_str(),
                     static_cast<int>(ui.recipe.x + ui.recipe.width + 8), static_cast<int>(ui.recipe.y + 5), 10, LIGHTGRAY);
            int hoverSlot = -1;
            for (int y = 0; y < kSlots; ++y) {
                for (int x = 0; x < kSlots; ++x) {
                    const Rectangle r{ui.grid.x + x * ui.slotPx, ui.grid.y + y * ui.slotPx, ui.slotPx, ui.slotPx};
                    const auto& list = slots.tiles[y * kSlots + x];
                    Color fill{30, 34, 40, 255};
                    std::string label;
                    if (!list.empty()) {
                        const TileRef& t = c.tiles[list.front()];
                        fill = t.missing ? MAGENTA : ColorBrightness(HashColor(TileRole(t)), -0.35f);
                        label = TileLabel(t);
                    }
                    DrawRectangleRec(r, fill);
                    const bool ring = x == 0 || y == 0 || x == kSlots - 1 || y == kSlots - 1;
                    const bool border = !ring && (x == 1 || y == 1 || x == kSlots - 2 || y == kSlots - 2);
                    DrawRectangleLinesEx(r, 1, ring ? Color{70, 70, 70, 255} : border ? Color{120, 120, 120, 255} : Color{200, 200, 200, 255});
                    if (!label.empty()) {
                        const std::string a = FitText(label, ui.slotPx - 4);
                        const std::string b = FitText(label.substr(a.size()), ui.slotPx - 4);
                        DrawText(a.c_str(), static_cast<int>(r.x + 2), static_cast<int>(r.y + 6), 10, RAYWHITE);
                        DrawText(b.c_str(), static_cast<int>(r.x + 2), static_cast<int>(r.y + 18), 10, RAYWHITE);
                        if (list.size() > 1)
                            DrawText(TextFormat("+%zu", list.size() - 1), static_cast<int>(r.x + 2), static_cast<int>(r.y + 29), 10, LIGHTGRAY);
                    }
                    if (x == slotX && y == slotY) DrawRectangleLinesEx(r, 3, SKYBLUE);
                    if (CheckCollisionPointRec(mouse, r)) hoverSlot = y * kSlots + x;
                }
            }
            DrawText("core 5x5 | border ring | outer ring; N is up", static_cast<int>(ui.grid.x),
                     static_cast<int>(ui.grid.y + ui.grid.height + 2), 10, GRAY);
            if (ui.popup) {
                const auto& list = slots.tiles[slotY * kSlots + slotX];
                DrawRectangleRec(ui.popupRect, Color{10, 14, 22, 235});
                DrawRectangleLinesEx(ui.popupRect, 1, SKYBLUE);
                DrawText(TextFormat("Slot %d,%d  (%s)  %zu tile(s)", slotX - kSlots / 2, kSlots / 2 - slotY,
                                    (slotX >= 2 && slotX <= 6 && slotY >= 2 && slotY <= 6) ? "core"
                                    : (slotX >= 1 && slotX <= 7 && slotY >= 1 && slotY <= 7) ? "border ring" : "outer ring",
                                    list.size()),
                         static_cast<int>(ui.popupRect.x + 8), static_cast<int>(ui.popupRect.y + 10), 10, YELLOW);
                DrawButton(ui.popupClose, "X", mouse);
                if (list.empty())
                    DrawText("No tile instance here (generated base floor / shell only).", static_cast<int>(ui.popupRect.x + 8),
                             static_cast<int>(ui.popupRect.y + 40), 10, LIGHTGRAY);
                for (size_t i = 0; i < ui.open.size(); ++i) {
                    const TileRef& t = c.tiles[ui.open[i].second];
                    const int ex = static_cast<int>(ui.popupRect.x + 8);
                    const int ey = static_cast<int>(ui.popupRect.y + 32 + i * kEntryHeight);
                    if (i) DrawLine(ex, ey - 4, static_cast<int>(ui.popupRect.x + ui.popupRect.width - 8), ey - 4, Color{60, 70, 90, 255});
                    DrawText(FitText(t.relative, ui.popupRect.width - 160).c_str(), ex, ey + 4, 10, t.missing ? MAGENTA : RAYWHITE);
                    DrawText(TextFormat("role %s   name %s", TileRole(t).c_str(), t.targetname.empty() ? "-" : t.targetname.c_str()),
                             ex, ey + 18, 10, LIGHTGRAY);
                    DrawText(TextFormat("origin %.0f %.0f %.0f   yaw %.0f   footprint %.1f x %.1f tiles%s", t.origin[0], t.origin[1],
                                        t.origin[2], t.angles[1], t.hasBounds ? (t.maxX - t.minX) / kTile : 0.0f,
                                        t.hasBounds ? (t.maxY - t.minY) / kTile : 0.0f, t.missing ? "   MISSING FILE" : ""),
                             ex, ey + 32, 10, GRAY);
                    DrawButton(ui.open[i].first, "Open in Hammer", mouse);
                }
                if (ui.hiddenEntries)
                    DrawText(TextFormat("... %d more (infill/overlapping)", ui.hiddenEntries), static_cast<int>(ui.popupRect.x + 8),
                             static_cast<int>(ui.popupRect.y + ui.popupRect.height - 16), 10, GRAY);
            }
            if (hoverSlot >= 0 && !slots.tiles[hoverSlot].empty()) {
                const std::string tip = c.tiles[slots.tiles[hoverSlot].front()].relative;
                const int w = MeasureText(tip.c_str(), 10) + 10;
                DrawRectangle(static_cast<int>(mouse.x + 14), static_cast<int>(mouse.y + 14), w, 18, Color{0, 0, 0, 220});
                DrawText(tip.c_str(), static_cast<int>(mouse.x + 19), static_cast<int>(mouse.y + 18), 10, RAYWHITE);
            }
        }
        if (GetTime() < statusUntil) {
            const int w = MeasureText(status.c_str(), 10) + 16;
            DrawRectangle(sw / 2 - w / 2, sh - 34, w, 22, Color{0, 0, 0, 200});
            DrawText(status.c_str(), sw / 2 - w / 2 + 8, sh - 28, 10, YELLOW);
        }
        EndDrawing();

        ++frame;
        if (IsKeyPressed(KEY_F12)) {
            Image image = LoadImageFromScreen();
            const std::string name = TextFormat("world-viewer-%d.png", frame);
            ExportImage(image, name.c_str());
            UnloadImage(image);
        }
        if (!options.screenshot.empty() && frame == options.frames) {
            Image image = LoadImageFromScreen();
            ExportImage(image, options.screenshot.string().c_str());
            UnloadImage(image);
            break;
        }
    }

    for (size_t i = 0; i < meshes.size(); ++i)
        if (hasMesh[i]) UnloadMesh(meshes[i]);
    UnloadShader(shader);
    CloseWindow();
    return 0;
}
