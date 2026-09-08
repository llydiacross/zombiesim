#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace zombiesim::walker {

inline constexpr std::uint16_t kInvalidCellId = 0xFFFF;

enum CellFlag : std::uint8_t {
    CellFlagNone = 0,
    CellFlagSafeZone = 1 << 0,
    CellFlagDeadZone = 1 << 1,
};

struct EdgeStatic {
    std::uint16_t targetCellId = kInvalidCellId;
    std::uint8_t direction = 0;
    std::uint8_t movementMask = 0;
    bool blocked = true;
    std::uint8_t baseCost = 1;
};

struct CellStatic {
    std::uint16_t cellId = kInvalidCellId;
    std::int16_t gridX = 0;
    std::int16_t gridY = 0;
    std::uint16_t dangerPermille = 0;
    std::uint16_t radiationPermille = 0;
    std::uint8_t flags = CellFlagNone;
    std::vector<EdgeStatic> edges;
};

struct WorldGraph {
    std::string profileId;
    std::string mapManifestSha256;
    std::string templatePlanSha256;
    std::uint64_t worldSeed = 0;
    std::uint32_t population = 0;
    std::uint64_t revisionHash = 0;
    std::vector<CellStatic> cells;

    [[nodiscard]] const CellStatic* FindCell(std::uint16_t cellId) const;
    [[nodiscard]] bool IsSafeZone(std::uint16_t cellId) const;
};

[[nodiscard]] std::uint64_t ComputeGraphRevisionHash(const WorldGraph& graph);

}  // namespace zombiesim::walker