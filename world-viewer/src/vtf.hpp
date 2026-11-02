#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "vpk.hpp"

namespace zmv {

struct VtfImage {
    int width = 0, height = 0;          // decoded mip size
    int fullWidth = 0, fullHeight = 0;  // top-level size, used for Source texture-axis scaling
    std::vector<uint8_t> rgba;          // width * height * 4
};

// Decodes the smallest mip whose larger side is at least `targetSize` (or the top mip),
// reading only the bytes needed. Frame 0 / face 0 / slice 0 only; envmaps are rejected.
bool LoadVtf(const GameFileSystem& fs, const std::string& path, int targetSize, VtfImage& out, std::string* why = nullptr);

}  // namespace zmv
