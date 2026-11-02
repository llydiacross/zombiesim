#pragma once

#include <cstdint>
#include <string>

#include "geometry.hpp"
#include "materials.hpp"
#include "vpk.hpp"

namespace zmv {

// Loads LOD0 of a compiled Source studio model (.mdl + .vvd + .dx90.vtx), using the first model of
// every body part and the requested skin family. Like the engine, non-$staticprop models are posed
// by frame 0 of their first sequence (skinned through each vertex's bone weights); $staticprop
// models keep their baked vertices. Vertices stay in model space; the caller applies the prop
// entity transform.
struct StudioLoadResult {
    MeshData mesh;
    uint64_t hash = 0;  // FNV-1a over the three files, for provenance
    std::string error;
    std::string poseInfo;  // diagnostic summary of the bones and the pose applied
};

bool LoadStudioModel(const GameFileSystem& fs, MaterialColors& colors, const std::string& modelPath, int skin,
                     StudioLoadResult& out);

}  // namespace zmv
