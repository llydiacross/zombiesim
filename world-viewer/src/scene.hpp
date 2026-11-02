#pragma once

#include <cstdint>
#include <filesystem>
#include <map>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "geometry.hpp"
#include "materials.hpp"

namespace zmv {

struct Landmark {
    std::string name;
    Rgb color;
};

struct District {
    std::string name;
    int x = 0, y = 0, radius = 0;
    Rgb color;
};

struct TileRef {
    std::filesystem::path file;  // absolute instance VMF
    std::string relative;        // path relative to the repository root
    std::string targetname;
    std::array<float, 3> origin{0, 0, 0};  // cell-local
    std::array<float, 3> angles{0, 0, 0};
    float minX = 0, minY = 0, maxX = 0, maxY = 0, minZ = 0, maxZ = 0;  // cell-local bounds of the instance's own geometry
    bool hasBounds = false;
    bool missing = false;
};

struct CellInfo {
    int x = 0, y = 0;            // plan grid (y grows southward)
    int logicalX = 0, logicalY = 0;
    bool empty = false;
    Rgb emptyColor{90, 90, 90};
    std::string recipe;           // file name of the recipe VMF
    std::filesystem::path recipePath;
    std::vector<TileRef> tiles;   // top-level func_instance placements in the recipe
    std::string topology;
    std::string environment;
    std::string orientation;
    int buildingTier = 0;
    int sceneryTier = 0;
    std::string district;
    double radiation = 0;
    double danger = 0;
    bool safeZone = false;
    std::vector<Landmark> landmarks;
    std::map<std::string, int> buildingCategories;
    size_t instanceCount = 0;
    size_t triangleCount = 0;
    int missingInstances = 0;
    bool recipeMissing = false;
};

struct DrawItem {
    int model = 0;
    bool shell = false;
    bool prop = false;  // studio model; drawn only when props are enabled
    int cell = 0;
    Mat4 world;
    float center[3] = {0, 0, 0};
    float radius = 0;
};

struct SceneStats {
    size_t models = 0;
    size_t instances = 0;
    size_t triangles = 0;
    size_t brushes = 0;
    size_t displacements = 0;
    size_t props = 0;
    size_t propInstances = 0;     // prop entities resolved to a loaded studio model
    size_t propTriangles = 0;     // triangles across all prop instances (not in `triangles`)
    size_t studioModels = 0;      // distinct .mdl + skin meshes loaded
    size_t failedProps = 0;       // prop entities whose model could not be read
    size_t failedSides = 0;
    size_t missingFiles = 0;
    size_t depthLimited = 0;
    size_t environmentLights = 0;
    double loadSeconds = 0;
};

class Scene {
public:
    bool Load(const std::filesystem::path& planPath, const std::filesystem::path& repoRoot, MaterialColors& colors,
              std::string& error);

    std::vector<VmfModel> models;
    std::vector<CellInfo> cells;
    std::vector<DrawItem> items;
    std::vector<LightDef> lights;  // world-space point and spot lights
    LightDef sun;                  // first light_environment found
    bool hasSun = false;
    std::vector<District> districts;
    std::vector<std::string> missingFiles;
    std::vector<std::string> failedStudioModels;  // unique "<path>: <reason>"
    SceneStats stats;
    int gridWidth = 0, gridHeight = 0;
    double pitch = 5760;
    double visualHalfExtent = 2880;
    std::string provenance;  // FNV-1a over plan, manifest and every loaded VMF
    std::filesystem::path planPath;
    std::filesystem::path manifestPath;

    int CellIndexAt(int x, int y) const;
    // World-space centre of a plan grid cell (Source units, +Y north).
    void CellCenter(int x, int y, double& wx, double& wy) const;

private:
    int ModelFor(const std::filesystem::path& file, MaterialColors& colors);
    int StudioFor(const std::string& modelPath, int skin);
    void Expand(int model, const Mat4& world, int depth, int cellIndex);
    std::unordered_map<std::string, int> modelIndex_;
    std::unordered_map<std::string, uint64_t> fileHashes_;
    std::filesystem::path repoRoot_;
    MaterialColors* colors_ = nullptr;
};

uint64_t Fnv1a(const std::string& data, uint64_t seed = 1469598103934665603ull);

}  // namespace zmv
