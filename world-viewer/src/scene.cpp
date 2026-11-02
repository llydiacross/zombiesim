#include "scene.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <nlohmann/json.hpp>

#include "keyvalues.hpp"
#include "studio.hpp"
#include "vpk.hpp"

namespace zmv {

namespace {

constexpr int kMaxInstanceDepth = 8;

Rgb JsonColor(const nlohmann::json& j, Rgb fallback = {128, 128, 128}) {
    if (j.is_object()) {
        return {static_cast<uint8_t>(j.value("red", 128)), static_cast<uint8_t>(j.value("green", 128)),
                static_cast<uint8_t>(j.value("blue", 128))};
    }
    if (j.is_array() && j.size() >= 3) {
        return {static_cast<uint8_t>(j[0].get<int>()), static_cast<uint8_t>(j[1].get<int>()),
                static_cast<uint8_t>(j[2].get<int>())};
    }
    return fallback;
}

std::string JsonString(const nlohmann::json& j, const char* key) {
    const auto it = j.find(key);
    if (it == j.end() || !it->is_string()) return {};
    return it->get<std::string>();
}

int JsonInt(const nlohmann::json& j, const char* key, int fallback = 0) {
    const auto it = j.find(key);
    if (it == j.end() || !it->is_number()) return fallback;
    return it->get<int>();
}

double JsonNestedNumber(const nlohmann::json& j, const char* object, const char* key) {
    const auto it = j.find(object);
    if (it == j.end() || !it->is_object()) return 0;
    const auto v = it->find(key);
    return (v != it->end() && v->is_number()) ? v->get<double>() : 0;
}

bool LoadJson(const std::filesystem::path& path, nlohmann::json& out, std::string& bytes, std::string& error) {
    if (!ReadFileBytes(path, bytes)) {
        error = "cannot read " + path.string();
        return false;
    }
    size_t start = 0;
    if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF && static_cast<unsigned char>(bytes[1]) == 0xBB &&
        static_cast<unsigned char>(bytes[2]) == 0xBF) {
        start = 3;
    }
    try {
        out = nlohmann::json::parse(bytes.begin() + static_cast<std::ptrdiff_t>(start), bytes.end());
    } catch (const std::exception& ex) {
        error = path.string() + ": " + ex.what();
        return false;
    }
    return true;
}

// tiletemplates/buildings/tile_skyscraper_ra_1aaa_2x.vmf -> "skyscraper_ra"
std::string BuildingCategory(const std::filesystem::path& file) {
    const std::string generic = ToLower(file.generic_string());
    if (generic.find("/tiletemplates/buildings/") == std::string::npos &&
        generic.find("/tiletemplates/army/") == std::string::npos) {
        return {};
    }
    std::string stem = ToLower(file.stem().string());
    if (stem.rfind("tile_", 0) == 0) stem = stem.substr(5);
    for (size_t i = 0; i + 1 < stem.size(); ++i) {
        if (stem[i] == '_' && std::isdigit(static_cast<unsigned char>(stem[i + 1]))) {
            stem.resize(i);
            break;
        }
    }
    return stem;
}

}  // namespace

uint64_t Fnv1a(const std::string& data, uint64_t seed) {
    uint64_t h = seed;
    for (unsigned char c : data) {
        h ^= c;
        h *= 1099511628211ull;
    }
    return h;
}

int Scene::CellIndexAt(int x, int y) const {
    for (size_t i = 0; i < cells.size(); ++i) {
        if (cells[i].x == x && cells[i].y == y) return static_cast<int>(i);
    }
    return -1;
}

void Scene::CellCenter(int x, int y, double& wx, double& wy) const {
    wx = x * pitch;
    wy = -y * pitch;
}

int Scene::ModelFor(const std::filesystem::path& file, MaterialColors& colors) {
    const std::string key = ToLower(file.lexically_normal().generic_string());
    const auto it = modelIndex_.find(key);
    if (it != modelIndex_.end()) return it->second;
    std::string bytes;
    if (!ReadFileBytes(file, bytes)) {
        modelIndex_.emplace(key, -1);
        missingFiles.push_back(file.lexically_normal().string());
        return -1;
    }
    fileHashes_.emplace(key, Fnv1a(bytes));
    VmfLoadOptions options;
    models.push_back(LoadVmf(file, colors, options));
    const int index = static_cast<int>(models.size() - 1);
    modelIndex_.emplace(key, index);
    return index;
}

int Scene::StudioFor(const std::string& modelPath, int skin) {
    const std::string key = "mdl:" + ToLower(modelPath) + "#" + std::to_string(skin);
    const auto it = modelIndex_.find(key);
    if (it != modelIndex_.end()) return it->second;
    StudioLoadResult result;
    if (!LoadStudioModel(colors_->FileSystem(), *colors_, modelPath, skin, result)) {
        modelIndex_.emplace(key, -1);
        failedStudioModels.push_back(result.error);
        return -1;
    }
    fileHashes_.emplace(key, result.hash);
    VmfModel model;
    model.mesh = std::move(result.mesh);
    model.studio = true;
    model.loaded = true;
    models.push_back(std::move(model));
    const int index = static_cast<int>(models.size() - 1);
    modelIndex_.emplace(key, index);
    ++stats.studioModels;
    return index;
}

void Scene::Expand(int model, const Mat4& world, int depth, int cellIndex) {
    const VmfModel& m = models[model];
    for (int pass = 0; pass < 2; ++pass) {
        const MeshData& mesh = pass == 0 ? m.mesh : m.shell;
        if (mesh.TriangleCount() == 0) continue;
        DrawItem item;
        item.model = model;
        item.shell = pass == 1;
        item.prop = m.studio;
        item.cell = cellIndex;
        item.world = world;
        float lo[3] = {1e30f, 1e30f, 1e30f}, hi[3] = {-1e30f, -1e30f, -1e30f};
        for (int c = 0; c < 8; ++c) {
            const float px = (c & 1) ? mesh.boundsMax[0] : mesh.boundsMin[0];
            const float py = (c & 2) ? mesh.boundsMax[1] : mesh.boundsMin[1];
            const float pz = (c & 4) ? mesh.boundsMax[2] : mesh.boundsMin[2];
            const auto t = world.TransformPoint(px, py, pz);
            for (int k = 0; k < 3; ++k) {
                lo[k] = std::min(lo[k], t[k]);
                hi[k] = std::max(hi[k], t[k]);
            }
        }
        float r2 = 0;
        for (int k = 0; k < 3; ++k) {
            item.center[k] = 0.5f * (lo[k] + hi[k]);
            const float h = 0.5f * (hi[k] - lo[k]);
            r2 += h * h;
        }
        item.radius = std::sqrt(r2);
        items.push_back(item);
        if (m.studio) {
            stats.propTriangles += mesh.TriangleCount();
            continue;
        }
        if (cellIndex >= 0) cells[cellIndex].triangleCount += mesh.TriangleCount();
        stats.triangles += mesh.TriangleCount();
    }

    // Copy: loading child models grows `models` and would invalidate `m`.
    for (const LightDef& local : m.lights) {
        LightDef light = local;
        light.position = world.TransformPoint(local.position[0], local.position[1], local.position[2]);
        const auto& w = world.m;
        const float dx = local.direction[0], dy = local.direction[1], dz = local.direction[2];
        float d[3] = {w[0] * dx + w[4] * dy + w[8] * dz, w[1] * dx + w[5] * dy + w[9] * dz, w[2] * dx + w[6] * dy + w[10] * dz};
        const float len = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        if (len > 1e-6f) light.direction = {d[0] / len, d[1] / len, d[2] / len};
        if (light.type == LightType::Environment) {
            ++stats.environmentLights;
            if (!hasSun) {
                sun = light;
                hasSun = true;
            }
        } else {
            lights.push_back(light);
        }
    }
    const std::vector<PropRef> props = m.propRefs;
    const std::vector<InstanceRef> instances = m.instances;
    for (const PropRef& prop : props) {
        const int child = StudioFor(prop.model, prop.skin);
        if (child < 0) {
            ++stats.failedProps;
            continue;
        }
        ++stats.propInstances;
        Expand(child, world * prop.local, depth + 1, cellIndex);
    }
    for (const InstanceRef& ref : instances) {
        if (depth >= kMaxInstanceDepth) {
            ++stats.depthLimited;
            continue;
        }
        const int child = ModelFor(ref.file, *colors_);
        if (cellIndex >= 0) ++cells[cellIndex].instanceCount;
        ++stats.instances;
        if (depth == 0 && cellIndex >= 0) {
            TileRef tile;
            tile.file = ref.file;
            tile.relative = ref.file.lexically_relative(repoRoot_).generic_string();
            if (tile.relative.empty() || tile.relative.rfind("..", 0) == 0) tile.relative = ref.file.generic_string();
            tile.targetname = ref.targetname;
            tile.origin = ref.origin;
            tile.angles = ref.angles;
            tile.missing = child < 0;
            if (child >= 0) {
                const MeshData& mesh = models[child].mesh;
                if (mesh.TriangleCount()) {
                    tile.minX = tile.minY = tile.minZ = 1e30f;
                    tile.maxX = tile.maxY = tile.maxZ = -1e30f;
                    for (int corner = 0; corner < 8; ++corner) {
                        const auto p = ref.local.TransformPoint((corner & 1) ? mesh.boundsMax[0] : mesh.boundsMin[0],
                                                                (corner & 2) ? mesh.boundsMax[1] : mesh.boundsMin[1],
                                                                (corner & 4) ? mesh.boundsMax[2] : mesh.boundsMin[2]);
                        tile.minX = std::min(tile.minX, p[0]);
                        tile.maxX = std::max(tile.maxX, p[0]);
                        tile.minY = std::min(tile.minY, p[1]);
                        tile.maxY = std::max(tile.maxY, p[1]);
                        tile.minZ = std::min(tile.minZ, p[2]);
                        tile.maxZ = std::max(tile.maxZ, p[2]);
                    }
                    tile.hasBounds = true;
                }
            }
            cells[cellIndex].tiles.push_back(std::move(tile));
        }
        if (child < 0) {
            if (cellIndex >= 0) ++cells[cellIndex].missingInstances;
            continue;
        }
        if (depth == 0 && cellIndex >= 0) {
            const std::string category = BuildingCategory(ref.file);
            if (!category.empty()) ++cells[cellIndex].buildingCategories[category];
        }
        Expand(child, world * ref.local, depth + 1, cellIndex);
    }
}

bool Scene::Load(const std::filesystem::path& plan, const std::filesystem::path& repoRoot, MaterialColors& colors,
                 std::string& error) {
    const auto started = std::chrono::steady_clock::now();
    repoRoot_ = repoRoot;
    colors_ = &colors;
    planPath = plan;

    nlohmann::json planJson, manifestJson;
    std::string planBytes, manifestBytes;
    if (!LoadJson(plan, planJson, planBytes, error)) return false;
    if (planJson.contains("cellBounds")) {
        const auto& b = planJson["cellBounds"];
        pitch = b.value("neighbourPitch", 5760.0);
        visualHalfExtent = b.value("visualHalfExtent", 2880.0);
    }
    const std::string mapData = JsonString(planJson, "mapData");
    if (!mapData.empty()) {
        manifestPath = plan.parent_path() / mapData;
        if (!LoadJson(manifestPath, manifestJson, manifestBytes, error)) return false;
    }

    std::unordered_map<long long, const nlohmann::json*> manifestCells;
    if (manifestJson.contains("cells")) {
        for (const auto& c : manifestJson["cells"]) {
            manifestCells[static_cast<long long>(c.value("x", 0)) * 100000 + c.value("y", 0)] = &c;
        }
    }
    if (manifestJson.contains("districts")) {
        for (const auto& d : manifestJson["districts"]) {
            District district;
            district.name = JsonString(d, "name");
            district.x = JsonInt(d, "x");
            district.y = JsonInt(d, "y");
            district.radius = JsonInt(d, "radius");
            if (d.contains("color")) district.color = JsonColor(d["color"]);
            districts.push_back(district);
        }
    }

    auto addCell = [&](const nlohmann::json& c, bool empty) {
        CellInfo cell;
        cell.x = JsonInt(c, "x");
        cell.y = JsonInt(c, "y");
        cell.logicalX = JsonInt(c, "worldX", cell.x);
        cell.logicalY = JsonInt(c, "worldY", cell.y);
        cell.empty = empty;
        cell.environment = JsonString(c, "environmentProfile");
        if (empty && c.contains("emptyColor")) cell.emptyColor = JsonColor(c["emptyColor"]);
        cell.topology = empty ? "empty" : JsonString(c, "topology");
        cell.orientation = JsonString(c, "orientation");
        cell.buildingTier = JsonInt(c, "buildingDensityTier");
        cell.sceneryTier = JsonInt(c, "sceneryDensityTier");
        cell.safeZone = c.contains("safeZoneEntrance") && !c["safeZoneEntrance"].is_null();
        cell.recipe = JsonString(c, "cellTemplateFilename");
        const auto found = manifestCells.find(static_cast<long long>(cell.x) * 100000 + cell.y);
        if (found != manifestCells.end()) {
            const nlohmann::json& mc = *found->second;
            if (mc.contains("district") && mc["district"].is_object()) cell.district = JsonString(mc["district"], "name");
            cell.radiation = JsonNestedNumber(mc, "radiation", "intensity");
            cell.danger = JsonNestedNumber(mc, "danger", "intensity");
            if (mc.contains("landmarks") && mc["landmarks"].is_array()) {
                for (const auto& l : mc["landmarks"]) {
                    if (!l.is_object()) continue;
                    Landmark landmark;
                    landmark.name = JsonString(l, "name");
                    if (l.contains("color")) landmark.color = JsonColor(l["color"]);
                    cell.landmarks.push_back(landmark);
                }
            }
            if (mc.contains("safeZone") && !mc["safeZone"].is_null()) cell.safeZone = true;
        }
        gridWidth = std::max(gridWidth, cell.x + 1);
        gridHeight = std::max(gridHeight, cell.y + 1);
        cells.push_back(cell);
        return static_cast<int>(cells.size() - 1);
    };

    for (const auto& c : planJson["cells"]) {
        const int index = addCell(c, false);
        std::string relative = JsonString(c, "cellTemplatePath");
        std::replace(relative.begin(), relative.end(), '\\', '/');
        const std::filesystem::path recipe = (repoRoot / relative).lexically_normal();
        cells[index].recipePath = recipe;
        const int model = ModelFor(recipe, colors);
        if (model < 0) {
            cells[index].recipeMissing = true;
            continue;
        }
        double wx, wy;
        CellCenter(cells[index].x, cells[index].y, wx, wy);
        Expand(model, Mat4::Translation(wx, wy, 0), 0, index);
    }
    if (planJson.contains("emptyCells")) {
        for (const auto& c : planJson["emptyCells"]) addCell(c, true);
    }

    uint64_t hash = Fnv1a(planBytes);
    hash = Fnv1a(manifestBytes, hash);
    std::vector<std::pair<std::string, uint64_t>> sorted(fileHashes_.begin(), fileHashes_.end());
    std::sort(sorted.begin(), sorted.end());
    for (const auto& [path, h] : sorted) {
        std::string relative = path;
        const std::string root = ToLower(repoRoot.lexically_normal().generic_string());
        if (relative.rfind(root, 0) == 0) relative = relative.substr(root.size());
        hash = Fnv1a(relative, hash);
        hash = Fnv1a(std::string(reinterpret_cast<const char*>(&h), sizeof(h)), hash);
    }
    char buffer[24];
    std::snprintf(buffer, sizeof(buffer), "%016llx", static_cast<unsigned long long>(hash));
    provenance = buffer;

    stats.models = models.size();
    stats.missingFiles = missingFiles.size();
    for (const auto& m : models) {
        stats.brushes += m.brushes;
        stats.displacements += m.displacements;
        stats.props += m.props;
        stats.failedSides += m.failedSides;
    }
    stats.loadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    return true;
}

}  // namespace zmv
