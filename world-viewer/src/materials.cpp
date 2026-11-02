#include "materials.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "keyvalues.hpp"
#include "vtf.hpp"

namespace zmv {

bool IsInvisibleToolMaterial(const std::string& lowerMaterial) {
    if (lowerMaterial.rfind("tools/", 0) != 0) return false;
    return lowerMaterial != "tools/toolsblack" && lowerMaterial != "tools/toolsblack_noportal";
}

namespace {

std::string NormalizePath(std::string s) {
    s = ToLower(s);
    std::replace(s.begin(), s.end(), '\\', '/');
    while (!s.empty() && s.front() == '/') s.erase(s.begin());
    return s;
}

uint8_t ToByte(float linear) {
    const float srgb = std::pow(std::clamp(linear, 0.0f, 1.0f), 1.0f / 2.2f);
    return static_cast<uint8_t>(std::lround(srgb * 255.0f));
}

bool KeywordColor(const std::string& m, Rgb& out) {
    struct Rule {
        const char* word;
        Rgb color;
    };
    static const Rule rules[] = {
        {"water", {52, 92, 120}},     {"grass", {86, 110, 52}},     {"blendgrass", {92, 104, 60}},
        {"sand", {176, 156, 116}},    {"dirt", {112, 92, 68}},      {"mud", {90, 76, 58}},
        {"rock", {118, 112, 104}},    {"cliff", {110, 104, 96}},    {"asphalt", {64, 64, 66}},
        {"road", {70, 70, 72}},       {"tar", {60, 60, 62}},        {"concrete", {150, 148, 142}},
        {"cement", {150, 148, 142}},  {"brick", {140, 78, 60}},     {"wood", {126, 92, 60}},
        {"metal", {120, 122, 126}},   {"glass", {120, 150, 170}},   {"window", {90, 116, 138}},
        {"roof", {82, 78, 76}},       {"tile", {170, 166, 156}},    {"plaster", {186, 180, 168}},
        {"snow", {230, 232, 236}},    {"black", {8, 8, 8}},         {"foliage", {70, 98, 46}},
        {"leaf", {70, 98, 46}},       {"hedge", {62, 90, 44}},      {"stone", {130, 126, 118}},
    };
    for (const auto& r : rules) {
        if (m.find(r.word) != std::string::npos) {
            out = r.color;
            return true;
        }
    }
    return false;
}

}  // namespace

namespace {

bool Truthy(const std::string* v) {
    return v && !v->empty() && (*v)[0] != '0';
}

void ApplyFields(const KVNode& block, std::string& baseTexture, bool& alphatest, bool& translucent) {
    if (const std::string* bt = block.Get("$basetexture")) baseTexture = *bt;
    if (const std::string* v = block.Get("$alphatest")) alphatest = Truthy(v);
    if (const std::string* v = block.Get("$translucent")) translucent = Truthy(v);
}

// Bilinear wrap-resample of an RGBA image into a square tile.
std::vector<uint8_t> ResampleTile(const VtfImage& img, int size) {
    std::vector<uint8_t> out(static_cast<size_t>(size) * size * 4);
    for (int y = 0; y < size; ++y) {
        const float fy = (y + 0.5f) * img.height / size - 0.5f;
        const int y0 = static_cast<int>(std::floor(fy));
        const float ty = fy - y0;
        for (int x = 0; x < size; ++x) {
            const float fx = (x + 0.5f) * img.width / size - 0.5f;
            const int x0 = static_cast<int>(std::floor(fx));
            const float tx = fx - x0;
            float acc[4] = {0, 0, 0, 0};
            for (int k = 0; k < 4; ++k) {
                const int sx = ((x0 + (k & 1)) % img.width + img.width) % img.width;
                const int sy = ((y0 + (k >> 1)) % img.height + img.height) % img.height;
                const float w = ((k & 1) ? tx : 1 - tx) * ((k >> 1) ? ty : 1 - ty);
                const uint8_t* p = &img.rgba[(static_cast<size_t>(sy) * img.width + sx) * 4];
                for (int c = 0; c < 4; ++c) acc[c] += p[c] * w;
            }
            uint8_t* d = &out[(static_cast<size_t>(y) * size + x) * 4];
            for (int c = 0; c < 4; ++c) d[c] = static_cast<uint8_t>(std::lround(std::clamp(acc[c], 0.0f, 255.0f)));
        }
    }
    return out;
}

bool Reflectivity(const GameFileSystem& fs, const std::string& path, Rgb& out) {
    std::string vtf;
    if (!fs.Read(path, vtf, 64) || vtf.size() < 44 || std::memcmp(vtf.data(), "VTF\0", 4) != 0) return false;
    float r[3];
    std::memcpy(r, vtf.data() + 32, sizeof(r));
    for (float f : r) {
        if (!std::isfinite(f)) return false;
    }
    out = {ToByte(r[0]), ToByte(r[1]), ToByte(r[2])};
    return true;
}

}  // namespace

bool MaterialColors::ReadVmt(const std::string& material, VmtFields& out, int depth) {
    if (depth > 4) return false;
    std::string text;
    if (!fs_.Read("materials/" + material + ".vmt", text)) return false;
    const KVNode root = ParseKeyValues(text);
    if (root.children.empty()) return false;
    const KVNode& shader = root.children.front();
    if (IEquals(shader.name, "patch")) {
        if (const std::string* include = shader.Get("include")) {
            std::string inc = NormalizePath(*include);
            if (inc.rfind("materials/", 0) == 0) inc = inc.substr(10);
            if (inc.size() > 4 && inc.compare(inc.size() - 4, 4, ".vmt") == 0) inc.resize(inc.size() - 4);
            ReadVmt(inc, out, depth + 1);
        }
        for (const char* section : {"insert", "replace"}) {
            if (const KVNode* block = shader.Child(section)) ApplyFields(*block, out.baseTexture, out.alphatest, out.translucent);
        }
    } else {
        out.shader = ToLower(shader.name);
        ApplyFields(shader, out.baseTexture, out.alphatest, out.translucent);
    }
    return true;
}

int MaterialColors::TileFor(const std::string& texture, MaterialInfo& info) {
    auto it = textures_.find(texture);
    if (it == textures_.end()) {
        TextureEntry entry;
        const std::string path = "materials/" + texture + ".vtf";
        VtfImage img;
        if (LoadVtf(fs_, path, kTileSize, img)) {
            entry.width = img.fullWidth;
            entry.height = img.fullHeight;
            double sum[3] = {0, 0, 0}, sumOpaque[3] = {0, 0, 0};
            size_t opaque = 0;
            const size_t n = static_cast<size_t>(img.width) * img.height;
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* p = &img.rgba[i * 4];
                for (int c = 0; c < 3; ++c) sum[c] += p[c];
                if (p[3] >= 128) {
                    for (int c = 0; c < 3; ++c) sumOpaque[c] += p[c];
                    ++opaque;
                }
            }
            auto avg = [](const double* s, size_t count) {
                count = std::max<size_t>(1, count);
                return Rgb{static_cast<uint8_t>(s[0] / count), static_cast<uint8_t>(s[1] / count), static_cast<uint8_t>(s[2] / count)};
            };
            entry.average = avg(sum, n);
            entry.averageOpaque = opaque ? avg(sumOpaque, opaque) : entry.average;
            entry.tile = static_cast<int>(tiles_.size());
            tiles_.push_back(ResampleTile(img, kTileSize));
        } else {
            ++textureFailures_;
            Rgb refl;
            if (Reflectivity(fs_, path, refl)) entry.average = entry.averageOpaque = refl, entry.width = -1;
        }
        it = textures_.emplace(texture, std::move(entry)).first;
    }
    const TextureEntry& e = it->second;
    if (e.tile < 0 && e.width != -1) return -2;  // nothing usable
    info.color = info.alpha == AlphaMode::Opaque ? e.average : e.averageOpaque;
    if (e.tile >= 0) {
        info.width = std::max(1, e.width);
        info.height = std::max(1, e.height);
    }
    return e.tile;
}

const MaterialInfo& MaterialColors::Info(const std::string& material) {
    const std::string key = NormalizePath(material);
    const auto it = cache_.find(key);
    if (it != cache_.end()) return it->second;

    MaterialInfo info;
    if (key == "halflife/black" || key == "tools/toolsblack" || key == "tools/toolsblack_noportal") {
        info.color = {6, 6, 6};
        return cache_.emplace(key, info).first->second;
    }
    VmtFields vmt;
    bool resolved = false;
    if (ReadVmt(key, vmt, 0) && !vmt.baseTexture.empty()) {
        info.alpha = vmt.translucent ? AlphaMode::Translucent : vmt.alphatest ? AlphaMode::AlphaTest : AlphaMode::Opaque;
        const int tile = TileFor(NormalizePath(vmt.baseTexture), info);
        if (tile != -2) {
            resolved = true;
            ++fromTextures_;
            // Water surfaces use their refraction/normal maps, not a meaningful base texture.
            info.tile = vmt.shader == "water" ? -1 : tile;
        }
    }
    if (!resolved && KeywordColor(key, info.color)) ++fromKeywords_;
    if (!resolved && std::getenv("ZMV_DEBUG_MATERIALS"))
        std::fprintf(stderr, "material unresolved: %s (vmt base '%s', shader '%s')\n", key.c_str(), vmt.baseTexture.c_str(),
                     vmt.shader.c_str());
    return cache_.emplace(key, info).first->second;
}

}  // namespace zmv
