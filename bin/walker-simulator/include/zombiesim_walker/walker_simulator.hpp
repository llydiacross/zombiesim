#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "zombiesim_walker/command_types.hpp"
#include "zombiesim_walker/walker_config.hpp"
#include "zombiesim_walker/world_graph.hpp"

namespace zombiesim::walker {

struct CellSummary {
    std::uint16_t cellId = kInvalidCellId;
    std::uint32_t ambientPopulation = 0;
    std::uint32_t reservedPopulation = 0;
    std::uint32_t materializedPopulation = 0;
    std::int32_t attraction = 0;
};

struct HordeSummary {
    std::uint64_t hordeId = 0;
    std::uint16_t cellId = kInvalidCellId;
    std::uint16_t nextCellId = kInvalidCellId;
    std::uint16_t count = 0;
    std::uint16_t reservedCount = 0;
    std::uint16_t progressPermille = 0;
};

struct TicketSummary {
    std::uint64_t ticketId = 0;
    std::uint64_t hordeId = 0;
    std::uint16_t cellId = kInvalidCellId;
    std::uint16_t localU = 0;
    std::uint16_t localV = 0;
    TicketState state = TicketState::Reserved;
    std::uint64_t expiresAtTick = 0;
};

struct OutputSnapshot {
    std::uint64_t tick = 0;
    std::uint64_t graphRevisionHash = 0;
    std::uint64_t stateHash = 0;
    std::uint64_t totalPopulation = 0;
    std::vector<CellSummary> cells;
    std::vector<HordeSummary> hordes;
    std::vector<TicketSummary> tickets;
};

class WalkerSimulator {
public:
    [[nodiscard]] bool Initialize(
        WorldGraph graph,
        WalkerConfig config,
        std::string* error = nullptr);
    [[nodiscard]] bool Submit(WalkerCommand command, std::string* error = nullptr);

    [[nodiscard]] const OutputSnapshot& Snapshot() const noexcept { return snapshot_; }
    [[nodiscard]] OutputSnapshot AdvanceOneTick();
    [[nodiscard]] std::vector<std::byte> ExportCheckpoint() const;
    [[nodiscard]] bool ImportCheckpoint(std::span<const std::byte> checkpoint, std::string* error = nullptr);

private:
    struct CellState {
        std::int32_t attraction = 0;
    };

    struct Horde {
        std::uint64_t hordeId = 0;
        std::uint16_t cellId = kInvalidCellId;
        std::uint16_t nextCellId = kInvalidCellId;
        std::uint16_t count = 0;
        std::uint16_t reservedCount = 0;
        std::uint16_t progressPermille = 0;
    };

    struct Ticket {
        std::uint64_t ticketId = 0;
        std::uint64_t hordeId = 0;
        std::uint16_t cellId = kInvalidCellId;
        std::uint16_t localU = 0;
        std::uint16_t localV = 0;
        TicketState state = TicketState::Reserved;
        std::uint64_t expiresAtTick = 0;
    };

    struct Attractor {
        std::uint16_t cellId = kInvalidCellId;
        std::uint16_t strength = 0;
        std::uint16_t radiusInCells = 0;
        std::uint64_t expiresAtTick = 0;
    };

    [[nodiscard]] std::optional<std::size_t> CellIndex(std::uint16_t cellId) const;
    [[nodiscard]] Horde* FindHorde(std::uint64_t hordeId);
    void ProcessCommands();
    void ApplyAttractors();
    void ApplyAttractor(const Attractor& attractor);
    void MoveHordes();
    void MergeAndSplitHordes();
    void ExpireTickets();
    [[nodiscard]] bool HasMaterializedTicket(std::uint64_t hordeId) const;
    [[nodiscard]] std::uint16_t ChooseNextCell(const Horde& horde) const;
    [[nodiscard]] std::uint64_t ComputeStateHash() const;
    void PublishSnapshot();

    std::optional<WorldGraph> graph_;
    WalkerConfig config_;
    std::uint64_t tick_ = 0;
    std::uint64_t nextHordeId_ = 1;
    std::uint64_t nextTicketId_ = 1;
    std::vector<CellState> cellStates_;
    std::vector<Horde> hordes_;
    std::map<std::uint64_t, Ticket> tickets_;
    std::vector<Attractor> attractors_;
    std::vector<WalkerCommand> pendingCommands_;
    std::vector<std::uint64_t> fulfilledRequestIds_;
    OutputSnapshot snapshot_;
};

}  // namespace zombiesim::walker