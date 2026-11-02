#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include "vpk.hpp"

namespace zmv {

struct Rgb {
    uint8_t r = 128, g = 128, b = 128;
};

enum class AlphaMode : uint8_t { Opaque = 0, AlphaTest = 1, Translucent = 2 };

struct MaterialInfo {
    Rgb color;              // average albedo (sRGB) used for untextured and distant rendering
    int tile = -1;          // index into MaterialColors::Tiles(), -1 = colour only
    int width = 512;        // top-level texture size for Source texture-axis scaling
    int height = 512;
    AlphaMode alpha = AlphaMode::Opaque;
};

// Resolves Source materials to an approximate albedo colour and, when available, a decoded
// base texture tile (kTileSize x kTileSize RGBA, sRGB) for the viewer atlas.
class MaterialColors {
public:
    static constexpr int kTileSize = 128;

    explicit MaterialColors(const GameFileSystem& fs) : fs_(fs) {}
    const MaterialInfo& Info(const std::string& material);
    Rgb Resolve(const std::string& material) { return Info(material).color; }
    const std::vector<std::vector<uint8_t>>& Tiles() const { return tiles_; }
    const GameFileSystem& FileSystem() const { return fs_; }
    size_t ResolvedFromTextures() const { return fromTextures_; }
    size_t ResolvedFromKeywords() const { return fromKeywords_; }
    size_t Materials() const { return cache_.size(); }
    size_t TextureFailures() const { return textureFailures_; }

private:
    struct VmtFields {
        std::string shader;
        std::string baseTexture;
        bool alphatest = false;
        bool translucent = false;
    };
    bool ReadVmt(const std::string& material, VmtFields& out, int depth);
    int TileFor(const std::string& texture, MaterialInfo& info);

    const GameFileSystem& fs_;
    std::unordered_map<std::string, MaterialInfo> cache_;
    struct TextureEntry {
        int tile = -1;
        int width = 0, height = 0;
        Rgb average;
        Rgb averageOpaque;
    };
    std::unordered_map<std::string, TextureEntry> textures_;
    std::vector<std::vector<uint8_t>> tiles_;
    size_t fromTextures_ = 0;
    size_t fromKeywords_ = 0;
    size_t textureFailures_ = 0;
};

// True for compile-only tool faces that never render (nodraw, clip, skybox, trigger...).
bool IsInvisibleToolMaterial(const std::string& lowerMaterial);

}  // namespace zmv
