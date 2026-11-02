#pragma once

#include <array>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

#include "materials.hpp"

namespace zmv {

// Column-major affine transform: m[col*4 + row], matching OpenGL/raylib column layout.
struct Mat4 {
    std::array<float, 16> m{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
    static Mat4 Translation(double x, double y, double z);
    // Source AngleMatrix(pitch, yaw, roll) followed by translation to origin.
    static Mat4 FromSourceAngles(double pitch, double yaw, double roll, double ox, double oy, double oz);
    Mat4 operator*(const Mat4& rhs) const;
    std::array<float, 3> TransformPoint(float x, float y, float z) const;
};

struct MeshData {
    std::vector<float> positions;  // xyz per vertex, non-indexed triangles
    std::vector<float> normals;
    std::vector<uint8_t> colors;  // rgba per vertex
    std::vector<float> uvs;       // Source texture-space u,v (in texture repeats)
    std::vector<float> surface;   // atlas tile (-1 = colour only), alpha mode
    std::array<float, 3> boundsMin{1e30f, 1e30f, 1e30f};
    std::array<float, 3> boundsMax{-1e30f, -1e30f, -1e30f};
    size_t TriangleCount() const { return positions.size() / 9; }
    void AddVertex(const double p[3], const double n[3], Rgb c, double u = 0, double v = 0, int tile = -1,
                   AlphaMode alpha = AlphaMode::Opaque);
};

enum class LightType : int { Point = 0, Spot = 1, Environment = 2 };

// A VRAD light entity converted to the viewer's linear-space lighting parameters.
struct LightDef {
    LightType type = LightType::Point;
    std::array<float, 3> position{0, 0, 0};
    std::array<float, 3> direction{0, 0, -1};  // light travel direction (spot / sun)
    std::array<float, 3> color{0, 0, 0};       // linear colour * intensity, normalised to the value at 100 units
    std::array<float, 3> ambient{0, 0, 0};     // environment only
    float constant = 1, linear = 0, quadratic = 0;
    float cutoff = 0;  // 0 = none
    float cosInner = 1, cosOuter = 0, exponent = 1;
};

struct InstanceRef {
    std::filesystem::path file;  // resolved absolute path
    std::string rawFile;
    std::string targetname;  // generator recipes use zm_tile_<role>_<x>_<y>
    std::array<float, 3> origin{0, 0, 0};
    std::array<float, 3> angles{0, 0, 0};
    Mat4 local;
};

// prop_static / prop_dynamic / prop_physics* entity: a studio model placed in this VMF.
struct PropRef {
    std::string model;  // e.g. models/props_c17/oildrum001.mdl
    int skin = 0;
    Mat4 local;         // angles, origin and uniform model scale
};

struct VmfModel {
    MeshData mesh;   // visible geometry
    MeshData shell;  // black world shell (halflife/black, toolsblack)
    std::vector<InstanceRef> instances;
    std::vector<PropRef> propRefs;
    bool studio = false;  // mesh comes from a .mdl rather than VMF brushes
    std::vector<LightDef> lights;  // model-local
    size_t brushes = 0;
    size_t displacements = 0;
    size_t props = 0;
    size_t failedSides = 0;
    bool loaded = false;
    std::string error;
};

struct VmfLoadOptions {
    bool skipSkyboxRoom = true;
};

VmfModel LoadVmf(const std::filesystem::path& path, MaterialColors& colors, const VmfLoadOptions& options);

}  // namespace zmv
