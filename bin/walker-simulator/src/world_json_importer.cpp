#include "zombiesim_walker/world_json_importer.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>
#include <stdexcept>
#include <string>
#include <unordered_set>

#include <nlohmann/json.hpp>

namespace zombiesim::walker {
namespace {

using Json = nlohmann::json;

constexpr std::uint8_t kRoadMask = 1 << 0;
constexpr std::uint8_t kMotorwayMask = 1 << 1;
constexpr std::uint8_t kMetroMask = 1 << 2;
constexpr std::uint8_t kOtherMask = 1 << 7;

[[nodiscard]] std::uint8_t DirectionFromString(const std::string& direction) {
    if (direction == "N") {
        return 0;
    }
    if (direction == "E") {
        return 1;
    }
    if (direction == "S") {
        return 2;
    }
    if (direction == "W") {
        return 3;
    }
    throw std::runtime_error("cell exit has an invalid direction");
}

[[nodiscard]] std::uint8_t MovementMaskFromString(const std::string& mode) {
    if (mode == "road") {
        return kRoadMask;
    }
    if (mode == "motorway") {
        return kMotorwayMask;
    }
    if (mode == "metro") {
        return kMetroMask;
    }
    return kOtherMask;
}

[[nodiscard]] std::uint16_t Permille(const Json& value, const char* fieldName) {
    if (!value.is_number()) {
        throw std::runtime_error(std::string(fieldName) + " must be numeric");
    }

    const auto raw = value.get<double>();
    if (!std::isfinite(raw) || raw < 0.0 || raw > 1.0) {
        throw std::runtime_error(std::string(fieldName) + " must be between 0 and 1");
    }

    return static_cast<std::uint16_t>(std::lround(raw * 1000.0));
}

[[nodiscard]] std::uint16_t CellId(const Json& value) {
    if (value.is_number_unsigned()) {
        const auto id = value.get<std::uint64_t>();
        if (id >= kInvalidCellId) {
            throw std::runtime_error("cell id is outside the supported range");
        }
        return static_cast<std::uint16_t>(id);
    }
    if (!value.is_number_integer()) {
        throw std::runtime_error("cell id must be an unsigned integer");
    }

    const auto id = value.get<std::int64_t>();
    if (id < 0 || id >= kInvalidCellId) {
        throw std::runtime_error("cell id is outside the supported range");
    }

    return static_cast<std::uint16_t>(id);
}

}  // namespace

WorldLoadResult LoadWorldJson(
    std::span<const std::byte> jsonBytes,
    std::string_view expectedProfileId) {
    try {
        if (jsonBytes.empty()) {
            return {std::nullopt, "world JSON is empty"};
        }

        const auto* text = reinterpret_cast<const char*>(jsonBytes.data());
        const Json root = Json::parse(text, text + jsonBytes.size());
        if (!root.is_object() || root.value("schemaVersion", 0) != 1) {
            return {std::nullopt, "unsupported or missing world schemaVersion"};
        }

        const auto& world = root.at("world");
        if (!world.is_object()) {
            return {std::nullopt, "world metadata must be an object"};
        }

        const auto profileId = world.at("mapDirectory").get<std::string>();
        if (profileId.empty() || profileId != expectedProfileId) {
            return {std::nullopt, "requested profile does not match world metadata"};
        }

        const auto& grid = world.at("grid");
        if (!grid.is_array() || grid.size() != 2 || !grid[0].is_number_integer() ||
            !grid[1].is_number_integer()) {
            return {std::nullopt, "world grid must contain two integer dimensions"};
        }

        const auto width = grid[0].get<std::int32_t>();
        const auto height = grid[1].get<std::int32_t>();
        if (width <= 0 || height <= 0 || width > std::numeric_limits<std::int16_t>::max() ||
            height > std::numeric_limits<std::int16_t>::max()) {
            return {std::nullopt, "world grid dimensions are invalid"};
        }

        const auto& gridOrigin = world.at("gridOrigin");
        if (!gridOrigin.is_array() || gridOrigin.size() != 2 ||
            !gridOrigin[0].is_number_integer() || !gridOrigin[1].is_number_integer()) {
            return {std::nullopt, "world gridOrigin must contain two integer coordinates"};
        }

        const auto originX = gridOrigin[0].get<std::int32_t>();
        const auto originY = gridOrigin[1].get<std::int32_t>();
        const auto& cellsJson = root.at("cells");
        if (!cellsJson.is_array() || cellsJson.empty() || cellsJson.size() > kInvalidCellId) {
            return {std::nullopt, "cells must be a non-empty supported-size array"};
        }

        WorldGraph graph;
        graph.profileId = profileId;
        graph.mapManifestSha256 = world.at("mapManifestSha256").get<std::string>();
        graph.templatePlanSha256 = world.at("templatePlanSha256").get<std::string>();
        if (graph.mapManifestSha256.empty() || graph.templatePlanSha256.empty()) {
            return {std::nullopt, "world manifest and template plan hashes are required"};
        }
        graph.worldSeed = world.at("seed").get<std::uint64_t>();
        if (!world.at("population").is_number_unsigned() && !world.at("population").is_number_integer()) {
            return {std::nullopt, "world population must be an unsigned integer"};
        }
        const auto population = world.at("population").get<std::int64_t>();
        if (population < 0 || static_cast<std::uint64_t>(population) > std::numeric_limits<std::uint32_t>::max()) {
            return {std::nullopt, "world population is outside the supported range"};
        }
        graph.population = static_cast<std::uint32_t>(population);
        graph.cells.reserve(cellsJson.size());

        std::unordered_set<std::uint16_t> knownIds;
        for (const auto& cellJson : cellsJson) {
            if (!cellJson.is_object()) {
                return {std::nullopt, "cell entry must be an object"};
            }

            CellStatic cell;
            cell.cellId = CellId(cellJson.at("id"));
            if (!knownIds.insert(cell.cellId).second) {
                return {std::nullopt, "world contains a duplicate cell id"};
            }
            if (cell.cellId >= static_cast<std::uint32_t>(width) * static_cast<std::uint32_t>(height)) {
                return {std::nullopt, "cell id is outside the declared world grid"};
            }

            const auto cellX = originX + static_cast<std::int32_t>(cell.cellId % width);
            const auto cellY = originY + static_cast<std::int32_t>(cell.cellId / width);
            if (cellX < std::numeric_limits<std::int16_t>::min() ||
                cellX > std::numeric_limits<std::int16_t>::max() ||
                cellY < std::numeric_limits<std::int16_t>::min() ||
                cellY > std::numeric_limits<std::int16_t>::max()) {
                return {std::nullopt, "cell grid coordinate is outside the supported range"};
            }

            cell.gridX = static_cast<std::int16_t>(cellX);
            cell.gridY = static_cast<std::int16_t>(cellY);
            cell.dangerPermille = Permille(cellJson.at("danger"), "danger");
            cell.radiationPermille = Permille(cellJson.at("radiation"), "radiation");
            if (!cellJson.at("safeZone").is_null()) {
                cell.flags |= CellFlagSafeZone;
            }
            if (cellJson.value("deadZone", false)) {
                cell.flags |= CellFlagDeadZone;
            }

            const auto& exits = cellJson.at("exits");
            if (!exits.is_array()) {
                return {std::nullopt, "cell exits must be an array"};
            }

            std::set<std::uint8_t> directions;
            for (const auto& exitJson : exits) {
                const auto direction = DirectionFromString(exitJson.at("direction").get<std::string>());
                if (!directions.insert(direction).second) {
                    return {std::nullopt, "cell has duplicate exit directions"};
                }

                EdgeStatic edge;
                edge.direction = direction;
                edge.targetCellId = CellId(exitJson.at("cell"));

                const auto& modes = exitJson.at("modes");
                if (!modes.is_array() || modes.empty()) {
                    return {std::nullopt, "cell exit must declare at least one movement mode"};
                }

                edge.blocked = true;
                for (const auto& modeJson : modes) {
                    if (!modeJson.is_object()) {
                        return {std::nullopt, "movement mode must be an object"};
                    }
                    edge.movementMask |= MovementMaskFromString(modeJson.at("type").get<std::string>());
                    if (!modeJson.value("blocked", false)) {
                        edge.blocked = false;
                    }
                }
                cell.edges.push_back(edge);
            }

            std::sort(
                cell.edges.begin(),
                cell.edges.end(),
                [](const EdgeStatic& left, const EdgeStatic& right) {
                    return left.direction < right.direction;
                });
            graph.cells.push_back(std::move(cell));
        }

        std::sort(
            graph.cells.begin(),
            graph.cells.end(),
            [](const CellStatic& left, const CellStatic& right) { return left.cellId < right.cellId; });
        for (const auto& cell : graph.cells) {
            for (const auto& edge : cell.edges) {
                if (!graph.FindCell(edge.targetCellId)) {
                    return {std::nullopt, "cell exit targets a missing cell"};
                }
            }
        }

        graph.revisionHash = ComputeGraphRevisionHash(graph);
        return {std::move(graph), {}};
    } catch (const nlohmann::json::exception& exception) {
        return {std::nullopt, std::string("invalid world JSON: ") + exception.what()};
    } catch (const std::exception& exception) {
        return {std::nullopt, exception.what()};
    }
}

}  // namespace zombiesim::walker