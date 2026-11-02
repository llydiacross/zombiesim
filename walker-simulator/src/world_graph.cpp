#include "zombiesim_walker/world_graph.hpp"

#include <algorithm>

#include "zombiesim_walker/deterministic_hash.hpp"

namespace zombiesim::walker {

const CellStatic* WorldGraph::FindCell(std::uint16_t cellId) const {
    const auto iterator = std::lower_bound(
        cells.begin(),
        cells.end(),
        cellId,
        [](const CellStatic& cell, std::uint16_t id) { return cell.cellId < id; });
    return iterator != cells.end() && iterator->cellId == cellId ? &*iterator : nullptr;
}

bool WorldGraph::IsSafeZone(std::uint16_t cellId) const {
    const auto* cell = FindCell(cellId);
    return cell != nullptr && (cell->flags & CellFlagSafeZone) != 0;
}

std::uint64_t ComputeGraphRevisionHash(const WorldGraph& graph) {
    DeterministicHasher hash;
    hash.AppendString(graph.profileId);
    hash.AppendString(graph.mapManifestSha256);
    hash.AppendString(graph.templatePlanSha256);
    hash.AppendInteger(graph.worldSeed);
    hash.AppendInteger(graph.population);
    hash.AppendInteger(static_cast<std::uint32_t>(graph.cells.size()));

    for (const auto& cell : graph.cells) {
        hash.AppendInteger(cell.cellId);
        hash.AppendInteger(static_cast<std::uint16_t>(cell.gridX));
        hash.AppendInteger(static_cast<std::uint16_t>(cell.gridY));
        hash.AppendInteger(cell.dangerPermille);
        hash.AppendInteger(cell.radiationPermille);
        hash.AppendInteger(cell.flags);
        hash.AppendInteger(static_cast<std::uint32_t>(cell.edges.size()));

        for (const auto& edge : cell.edges) {
            hash.AppendInteger(edge.targetCellId);
            hash.AppendInteger(edge.direction);
            hash.AppendInteger(edge.movementMask);
            hash.AppendBoolean(edge.blocked);
            hash.AppendInteger(edge.baseCost);
        }
    }

    return hash.Value();
}

}  // namespace zombiesim::walker