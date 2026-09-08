#include "zombiesim_walker/walker_simulator.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <queue>
#include <set>
#include <type_traits>

#include "zombiesim_walker/deterministic_hash.hpp"

namespace zombiesim::walker {
namespace {

constexpr std::array<std::byte, 8> kCheckpointMagic = {
    std::byte{'Z'}, std::byte{'M'}, std::byte{'W'}, std::byte{'A'},
    std::byte{'L'}, std::byte{'K'}, std::byte{'0'}, std::byte{'1'},
};
constexpr std::uint16_t kCheckpointFormatVersion = 1;

[[nodiscard]] std::uint64_t Mix(std::uint64_t value) {
    value += 0x9E3779B97F4A7C15ULL;
    value = (value ^ (value >> 30U)) * 0xBF58476D1CE4E5B9ULL;
    value = (value ^ (value >> 27U)) * 0x94D049BB133111EBULL;
    return value ^ (value >> 31U);
}

void SetError(std::string* error, const char* message) {
    if (error != nullptr) {
        *error = message;
    }
}

template <typename Integer>
void WriteInteger(std::vector<std::byte>& output, Integer value) {
    using Unsigned = std::make_unsigned_t<Integer>;
    const auto unsignedValue = static_cast<Unsigned>(value);
    for (std::size_t byteIndex = 0; byteIndex < sizeof(Unsigned); ++byteIndex) {
        output.push_back(static_cast<std::byte>(unsignedValue >> (byteIndex * 8U)));
    }
}

template <typename Integer>
[[nodiscard]] bool ReadInteger(
    std::span<const std::byte> input,
    std::size_t& offset,
    Integer& value) {
    using Unsigned = std::make_unsigned_t<Integer>;
    if (input.size() - offset < sizeof(Unsigned)) {
        return false;
    }

    Unsigned result = 0;
    for (std::size_t byteIndex = 0; byteIndex < sizeof(Unsigned); ++byteIndex) {
        const auto byte = static_cast<Unsigned>(std::to_integer<std::uint8_t>(input[offset++]));
        result = static_cast<Unsigned>(
            result | static_cast<Unsigned>(byte << (byteIndex * 8U)));
    }
    value = static_cast<Integer>(result);
    return true;
}

[[nodiscard]] std::uint64_t HashBytes(std::span<const std::byte> bytes) {
    DeterministicHasher hash;
    for (const auto byte : bytes) {
        hash.AppendByte(std::to_integer<std::uint8_t>(byte));
    }
    return hash.Value();
}

}  // namespace

bool WalkerSimulator::Initialize(WorldGraph graph, WalkerConfig config, std::string* error) {
    std::string configError;
    if (!ValidateWalkerConfig(config, &configError)) {
        if (error != nullptr) {
            *error = configError;
        }
        return false;
    }
    if (graph.cells.empty() || graph.revisionHash == 0 ||
        graph.revisionHash != ComputeGraphRevisionHash(graph)) {
        SetError(error, "world graph is missing or has an invalid revision hash");
        return false;
    }

    graph_ = std::move(graph);
    config_ = config;
    tick_ = 0;
    nextHordeId_ = 1;
    nextTicketId_ = 1;
    cellStates_.assign(graph_->cells.size(), {});
    hordes_.clear();
    tickets_.clear();
    attractors_.clear();
    pendingCommands_.clear();
    fulfilledRequestIds_.clear();

    std::vector<std::uint32_t> populationByCell(graph_->cells.size(), 0);
    std::vector<std::uint64_t> remainders(graph_->cells.size(), 0);
    std::uint64_t totalDanger = 0;
    std::vector<std::size_t> eligibleCellIndexes;
    for (std::size_t index = 0; index < graph_->cells.size(); ++index) {
        const auto& cell = graph_->cells[index];
        if ((cell.flags & CellFlagSafeZone) == 0) {
            eligibleCellIndexes.push_back(index);
            totalDanger += cell.dangerPermille;
        }
    }
    if (graph_->population > 0 && eligibleCellIndexes.empty()) {
        SetError(error, "world population cannot be assigned because every cell is a safe zone");
        return false;
    }
    if (eligibleCellIndexes.empty()) {
        PublishSnapshot();
        return true;
    }
    if (totalDanger == 0) {
        const auto basePopulation = static_cast<std::uint32_t>(graph_->population / eligibleCellIndexes.size());
        auto remainingPopulation = static_cast<std::uint32_t>(graph_->population % eligibleCellIndexes.size());
        for (const auto index : eligibleCellIndexes) {
            populationByCell[index] = basePopulation + (remainingPopulation-- > 0 ? 1U : 0U);
        }
    } else {
        std::uint64_t assignedPopulation = 0;
        for (const auto index : eligibleCellIndexes) {
            const auto weightedPopulation = static_cast<std::uint64_t>(graph_->population) * graph_->cells[index].dangerPermille;
            populationByCell[index] = static_cast<std::uint32_t>(weightedPopulation / totalDanger);
            remainders[index] = weightedPopulation % totalDanger;
            assignedPopulation += populationByCell[index];
        }

        std::sort(
            eligibleCellIndexes.begin(),
            eligibleCellIndexes.end(),
            [this, &remainders](std::size_t left, std::size_t right) {
                if (remainders[left] != remainders[right]) {
                    return remainders[left] > remainders[right];
                }
                return graph_->cells[left].cellId < graph_->cells[right].cellId;
            });
        auto remainingPopulation = graph_->population - assignedPopulation;
        for (std::size_t index = 0; remainingPopulation > 0; ++index, --remainingPopulation) {
            ++populationByCell[eligibleCellIndexes[index]];
        }
    }

    std::uint32_t redistributedPopulation = 0;
    std::vector<std::size_t> groupableCellIndexes;
    for (const auto index : eligibleCellIndexes) {
        const auto population = populationByCell[index];
        if (population > 0 && population < config_.minimumGroupSize) {
            redistributedPopulation += population;
            populationByCell[index] = 0;
        } else if (population >= config_.minimumGroupSize) {
            groupableCellIndexes.push_back(index);
        }
    }
    if (redistributedPopulation > 0 && groupableCellIndexes.empty()) {
        populationByCell[eligibleCellIndexes.front()] = redistributedPopulation;
        groupableCellIndexes.push_back(eligibleCellIndexes.front());
        redistributedPopulation = 0;
    }
    for (std::size_t index = 0; redistributedPopulation > 0; ++index, --redistributedPopulation) {
        ++populationByCell[groupableCellIndexes[index % groupableCellIndexes.size()]];
    }

    for (std::size_t cellIndex = 0; cellIndex < graph_->cells.size(); ++cellIndex) {
        const auto& cell = graph_->cells[cellIndex];
        auto remaining = populationByCell[cellIndex];
        if (remaining == 0) {
            continue;
        }

        while (remaining > config_.maximumGroupSize) {
            auto groupSize = static_cast<std::uint32_t>(config_.maximumGroupSize);
            const auto tail = remaining - groupSize;
            if (tail < config_.minimumGroupSize) {
                groupSize -= config_.minimumGroupSize - tail;
            }
            hordes_.push_back({
                .hordeId = nextHordeId_++,
                .cellId = cell.cellId,
                .count = static_cast<std::uint16_t>(groupSize),
            });
            remaining -= groupSize;
        }

        hordes_.push_back({
            .hordeId = nextHordeId_++,
            .cellId = cell.cellId,
            .count = static_cast<std::uint16_t>(remaining),
        });
    }

    PublishSnapshot();
    return true;
}

bool WalkerSimulator::Submit(WalkerCommand command, std::string* error) {
    if (!graph_) {
        SetError(error, "walker simulator is not initialized");
        return false;
    }

    const auto valid = std::visit(
        [this, error](const auto& typedCommand) {
            using Command = std::decay_t<decltype(typedCommand)>;
            if constexpr (std::is_same_v<Command, NoiseCommand>) {
                if (!CellIndex(typedCommand.cellId) || typedCommand.strength == 0 ||
                    typedCommand.durationTicks == 0) {
                    SetError(error, "noise command is invalid");
                    return false;
                }
            } else if constexpr (std::is_same_v<Command, RequestSpawnTicketsCommand>) {
                if (!CellIndex(typedCommand.cellId) || graph_->IsSafeZone(typedCommand.cellId) ||
                    typedCommand.maximumCount == 0 ||
                    typedCommand.maximumCount > config_.maximumTicketsPerRequest ||
                    typedCommand.requestId == 0) {
                    SetError(error, "ticket request command is invalid");
                    return false;
                }
            } else if (typedCommand.ticketId == 0) {
                SetError(error, "ticket command is invalid");
                return false;
            }
            return true;
        },
        command);
    if (!valid) {
        return false;
    }

    pendingCommands_.push_back(std::move(command));
    return true;
}

OutputSnapshot WalkerSimulator::AdvanceOneTick() {
    if (!graph_) {
        return snapshot_;
    }

    ++tick_;
    for (auto& cellState : cellStates_) {
        cellState.attraction = static_cast<std::int32_t>(
            static_cast<std::int64_t>(cellState.attraction) * config_.attractionDecayPermille / 1000);
    }
    ProcessCommands();
    ApplyAttractors();
    MoveHordes();
    MergeAndSplitHordes();
    ExpireTickets();
    PublishSnapshot();
    return snapshot_;
}

std::optional<std::size_t> WalkerSimulator::CellIndex(std::uint16_t cellId) const {
    if (!graph_) {
        return std::nullopt;
    }

    const auto iterator = std::lower_bound(
        graph_->cells.begin(),
        graph_->cells.end(),
        cellId,
        [](const CellStatic& cell, std::uint16_t id) { return cell.cellId < id; });
    if (iterator == graph_->cells.end() || iterator->cellId != cellId) {
        return std::nullopt;
    }
    return static_cast<std::size_t>(std::distance(graph_->cells.begin(), iterator));
}

WalkerSimulator::Horde* WalkerSimulator::FindHorde(std::uint64_t hordeId) {
    const auto iterator = std::find_if(
        hordes_.begin(),
        hordes_.end(),
        [hordeId](const Horde& horde) { return horde.hordeId == hordeId; });
    return iterator == hordes_.end() ? nullptr : &*iterator;
}

void WalkerSimulator::ProcessCommands() {
    for (const auto& command : pendingCommands_) {
        std::visit(
            [this](const auto& typedCommand) {
                using Command = std::decay_t<decltype(typedCommand)>;
                if constexpr (std::is_same_v<Command, NoiseCommand>) {
                    attractors_.push_back({
                        .cellId = typedCommand.cellId,
                        .strength = typedCommand.strength,
                        .radiusInCells = typedCommand.radiusInCells,
                        .expiresAtTick = tick_ + typedCommand.durationTicks,
                    });
                } else if constexpr (std::is_same_v<Command, RequestSpawnTicketsCommand>) {
                    if (std::binary_search(
                            fulfilledRequestIds_.begin(),
                            fulfilledRequestIds_.end(),
                            typedCommand.requestId)) {
                        return;
                    }
                    fulfilledRequestIds_.insert(
                        std::upper_bound(
                            fulfilledRequestIds_.begin(),
                            fulfilledRequestIds_.end(),
                            typedCommand.requestId),
                        typedCommand.requestId);

                    auto remaining = typedCommand.maximumCount;
                    for (auto& horde : hordes_) {
                        if (remaining == 0) {
                            break;
                        }
                        if (horde.cellId != typedCommand.cellId || horde.count <= horde.reservedCount) {
                            continue;
                        }

                        const auto available = static_cast<std::uint16_t>(horde.count - horde.reservedCount);
                        const auto toReserve = std::min(available, remaining);
                        for (std::uint16_t index = 0; index < toReserve; ++index) {
                            const auto random = Mix(
                                graph_->worldSeed ^ horde.hordeId ^ nextTicketId_ ^ tick_);
                            tickets_.emplace(
                                nextTicketId_,
                                Ticket{
                                    .ticketId = nextTicketId_,
                                    .hordeId = horde.hordeId,
                                    .cellId = horde.cellId,
                                    .localU = static_cast<std::uint16_t>(random & 0xFFFFU),
                                    .localV = static_cast<std::uint16_t>((random >> 16U) & 0xFFFFU),
                                    .state = TicketState::Reserved,
                                    .expiresAtTick = tick_ + config_.ticketLifetimeTicks,
                                });
                            ++nextTicketId_;
                            ++horde.reservedCount;
                            --remaining;
                        }
                    }
                } else {
                    const auto ticketIterator = tickets_.find(typedCommand.ticketId);
                    if (ticketIterator == tickets_.end()) {
                        return;
                    }
                    auto& ticket = ticketIterator->second;
                    auto* horde = FindHorde(ticket.hordeId);
                    if (horde == nullptr) {
                        return;
                    }

                    if constexpr (std::is_same_v<Command, AcknowledgeTicketCommand>) {
                        if (ticket.state == TicketState::Reserved && horde->reservedCount > 0 && horde->count > 0) {
                            --horde->reservedCount;
                            --horde->count;
                            ticket.state = TicketState::Materialized;
                        }
                    } else if constexpr (std::is_same_v<Command, RejectTicketCommand>) {
                        if (ticket.state == TicketState::Reserved && horde->reservedCount > 0) {
                            --horde->reservedCount;
                            ticket.state = TicketState::Rejected;
                        }
                    } else if constexpr (std::is_same_v<Command, ResolveTicketCommand>) {
                        if (ticket.state == TicketState::Materialized) {
                            if (typedCommand.killed) {
                                ticket.state = TicketState::Killed;
                            } else {
                                ++horde->count;
                                ticket.state = TicketState::Despawned;
                            }
                        }
                    }
                }
            },
            command);
    }
    pendingCommands_.clear();
}

void WalkerSimulator::ApplyAttractors() {
    for (const auto& attractor : attractors_) {
        if (attractor.expiresAtTick >= tick_) {
            ApplyAttractor(attractor);
        }
    }
    std::erase_if(attractors_, [this](const Attractor& attractor) {
        return attractor.expiresAtTick < tick_;
    });
}

void WalkerSimulator::ApplyAttractor(const Attractor& attractor) {
    std::queue<std::pair<std::uint16_t, std::uint16_t>> search;
    std::set<std::uint16_t> visited;
    search.push({attractor.cellId, 0});
    visited.insert(attractor.cellId);

    while (!search.empty()) {
        const auto [cellId, distance] = search.front();
        search.pop();

        if (const auto index = CellIndex(cellId)) {
            const auto contribution = static_cast<std::int32_t>(attractor.strength / (distance + 1U));
            const auto capacity = std::numeric_limits<std::int32_t>::max() - cellStates_[*index].attraction;
            cellStates_[*index].attraction += std::min(contribution, capacity);
        }
        if (distance >= attractor.radiusInCells) {
            continue;
        }

        const auto* cell = graph_->FindCell(cellId);
        for (const auto& edge : cell->edges) {
            if (!edge.blocked && visited.insert(edge.targetCellId).second) {
                search.push({edge.targetCellId, static_cast<std::uint16_t>(distance + 1U)});
            }
        }
    }
}

void WalkerSimulator::MoveHordes() {
    for (auto& horde : hordes_) {
        if (horde.count == 0 || horde.reservedCount != 0) {
            continue;
        }
        if (horde.nextCellId == kInvalidCellId) {
            horde.nextCellId = ChooseNextCell(horde);
        }
        if (horde.nextCellId == kInvalidCellId) {
            continue;
        }

        const auto progress = static_cast<std::uint32_t>(horde.progressPermille) + config_.progressPerTick;
        if (progress >= 1000) {
            horde.cellId = horde.nextCellId;
            horde.nextCellId = kInvalidCellId;
            horde.progressPermille = 0;
        } else {
            horde.progressPermille = static_cast<std::uint16_t>(progress);
        }
    }
}

void WalkerSimulator::MergeAndSplitHordes() {
    std::sort(
        hordes_.begin(),
        hordes_.end(),
        [](const Horde& left, const Horde& right) { return left.hordeId < right.hordeId; });

    std::vector<Horde> merged;
    merged.reserve(hordes_.size());
    for (const auto& horde : hordes_) {
        const auto canMerge = horde.nextCellId == kInvalidCellId && horde.reservedCount == 0 &&
                              !HasMaterializedTicket(horde.hordeId);
        if (canMerge) {
            const auto destination = std::find_if(
                merged.begin(),
                merged.end(),
                [this, &horde](const Horde& candidate) {
                    return candidate.cellId == horde.cellId &&
                           candidate.nextCellId == kInvalidCellId &&
                           candidate.reservedCount == 0 &&
                           !HasMaterializedTicket(candidate.hordeId) &&
                           static_cast<std::uint32_t>(candidate.count) + horde.count <=
                               config_.maximumGroupSize;
                });
            if (destination != merged.end()) {
                destination->count = static_cast<std::uint16_t>(destination->count + horde.count);
                continue;
            }
        }
        merged.push_back(horde);
    }

    std::vector<Horde> normalized;
    normalized.reserve(merged.size());
    for (const auto& horde : merged) {
        if (horde.reservedCount != 0 || HasMaterializedTicket(horde.hordeId) ||
            horde.count <= config_.maximumGroupSize) {
            normalized.push_back(horde);
            continue;
        }

        auto remaining = static_cast<std::uint32_t>(horde.count);
        bool useOriginalId = true;
        while (remaining > 0) {
            auto chunk = std::min(remaining, static_cast<std::uint32_t>(config_.maximumGroupSize));
            const auto tail = remaining - chunk;
            if (tail > 0 && tail < config_.minimumGroupSize) {
                chunk -= config_.minimumGroupSize - tail;
            }

            auto split = horde;
            split.hordeId = useOriginalId ? horde.hordeId : nextHordeId_++;
            split.count = static_cast<std::uint16_t>(chunk);
            split.reservedCount = 0;
            normalized.push_back(split);
            remaining -= chunk;
            useOriginalId = false;
        }
    }
    hordes_ = std::move(normalized);
    std::sort(
        hordes_.begin(),
        hordes_.end(),
        [](const Horde& left, const Horde& right) { return left.hordeId < right.hordeId; });
}

void WalkerSimulator::ExpireTickets() {
    for (auto& [ticketId, ticket] : tickets_) {
        static_cast<void>(ticketId);
        if (ticket.state != TicketState::Reserved || ticket.expiresAtTick >= tick_) {
            continue;
        }
        if (auto* horde = FindHorde(ticket.hordeId); horde != nullptr && horde->reservedCount > 0) {
            --horde->reservedCount;
        }
        ticket.state = TicketState::Expired;
    }
}

bool WalkerSimulator::HasMaterializedTicket(std::uint64_t hordeId) const {
    return std::any_of(
        tickets_.begin(),
        tickets_.end(),
        [hordeId](const auto& entry) {
            return entry.second.hordeId == hordeId && entry.second.state == TicketState::Materialized;
        });
}

std::uint16_t WalkerSimulator::ChooseNextCell(const Horde& horde) const {
    const auto* cell = graph_->FindCell(horde.cellId);
    std::uint16_t selected = kInvalidCellId;
    std::int64_t bestScore = std::numeric_limits<std::int64_t>::min();

    for (const auto& edge : cell->edges) {
        if (edge.blocked || graph_->IsSafeZone(edge.targetCellId)) {
            continue;
        }
        const auto targetIndex = CellIndex(edge.targetCellId);
        const auto noise = static_cast<std::int64_t>(Mix(
            graph_->worldSeed ^ horde.hordeId ^ (tick_ << 32U) ^ edge.targetCellId) & 0x1FU);
        const auto score = static_cast<std::int64_t>(cellStates_[*targetIndex].attraction) + noise;
        if (score > bestScore || (score == bestScore && edge.targetCellId < selected)) {
            bestScore = score;
            selected = edge.targetCellId;
        }
    }
    return selected;
}

std::uint64_t WalkerSimulator::ComputeStateHash() const {
    DeterministicHasher hash;
    hash.AppendInteger(graph_->revisionHash);
    hash.AppendInteger(ComputeWalkerConfigHash(config_));
    hash.AppendInteger(tick_);
    hash.AppendInteger(nextHordeId_);
    hash.AppendInteger(nextTicketId_);
    for (const auto& state : cellStates_) {
        hash.AppendInteger(state.attraction);
    }
    for (const auto& horde : hordes_) {
        hash.AppendInteger(horde.hordeId);
        hash.AppendInteger(horde.cellId);
        hash.AppendInteger(horde.nextCellId);
        hash.AppendInteger(horde.count);
        hash.AppendInteger(horde.reservedCount);
        hash.AppendInteger(horde.progressPermille);
    }
    for (const auto& [ticketId, ticket] : tickets_) {
        hash.AppendInteger(ticketId);
        hash.AppendInteger(ticket.hordeId);
        hash.AppendInteger(ticket.cellId);
        hash.AppendInteger(ticket.localU);
        hash.AppendInteger(ticket.localV);
        hash.AppendInteger(static_cast<std::uint8_t>(ticket.state));
        hash.AppendInteger(ticket.expiresAtTick);
    }
    for (const auto& attractor : attractors_) {
        hash.AppendInteger(attractor.cellId);
        hash.AppendInteger(attractor.strength);
        hash.AppendInteger(attractor.radiusInCells);
        hash.AppendInteger(attractor.expiresAtTick);
    }
    for (const auto requestId : fulfilledRequestIds_) {
        hash.AppendInteger(requestId);
    }
    return hash.Value();
}

void WalkerSimulator::PublishSnapshot() {
    snapshot_ = {};
    snapshot_.tick = tick_;
    snapshot_.graphRevisionHash = graph_ ? graph_->revisionHash : 0;
    snapshot_.cells.reserve(cellStates_.size());
    for (std::size_t index = 0; index < cellStates_.size(); ++index) {
        snapshot_.cells.push_back({
            .cellId = graph_->cells[index].cellId,
            .attraction = cellStates_[index].attraction,
        });
    }

    snapshot_.hordes.reserve(hordes_.size());
    for (const auto& horde : hordes_) {
        const auto index = CellIndex(horde.cellId);
        const auto ambient = static_cast<std::uint32_t>(horde.count - horde.reservedCount);
        snapshot_.cells[*index].ambientPopulation += ambient;
        snapshot_.cells[*index].reservedPopulation += horde.reservedCount;
        snapshot_.totalPopulation += horde.count;
        snapshot_.hordes.push_back({
            .hordeId = horde.hordeId,
            .cellId = horde.cellId,
            .nextCellId = horde.nextCellId,
            .count = horde.count,
            .reservedCount = horde.reservedCount,
            .progressPermille = horde.progressPermille,
        });
    }

    snapshot_.tickets.reserve(tickets_.size());
    for (const auto& [ticketId, ticket] : tickets_) {
        static_cast<void>(ticketId);
        if (ticket.state == TicketState::Materialized) {
            const auto index = CellIndex(ticket.cellId);
            ++snapshot_.cells[*index].materializedPopulation;
            ++snapshot_.totalPopulation;
        }
        snapshot_.tickets.push_back({
            .ticketId = ticket.ticketId,
            .hordeId = ticket.hordeId,
            .cellId = ticket.cellId,
            .localU = ticket.localU,
            .localV = ticket.localV,
            .state = ticket.state,
            .expiresAtTick = ticket.expiresAtTick,
        });
    }
    snapshot_.stateHash = graph_ ? ComputeStateHash() : 0;
}

std::vector<std::byte> WalkerSimulator::ExportCheckpoint() const {
    if (!graph_) {
        return {};
    }

    std::vector<std::byte> payload;
    WriteInteger(payload, tick_);
    WriteInteger(payload, nextHordeId_);
    WriteInteger(payload, nextTicketId_);
    WriteInteger(payload, static_cast<std::uint32_t>(cellStates_.size()));
    for (const auto& cellState : cellStates_) {
        WriteInteger(payload, cellState.attraction);
    }
    WriteInteger(payload, static_cast<std::uint32_t>(hordes_.size()));
    for (const auto& horde : hordes_) {
        WriteInteger(payload, horde.hordeId);
        WriteInteger(payload, horde.cellId);
        WriteInteger(payload, horde.nextCellId);
        WriteInteger(payload, horde.count);
        WriteInteger(payload, horde.reservedCount);
        WriteInteger(payload, horde.progressPermille);
    }
    WriteInteger(payload, static_cast<std::uint32_t>(tickets_.size()));
    for (const auto& [ticketId, ticket] : tickets_) {
        static_cast<void>(ticketId);
        WriteInteger(payload, ticket.ticketId);
        WriteInteger(payload, ticket.hordeId);
        WriteInteger(payload, ticket.cellId);
        WriteInteger(payload, ticket.localU);
        WriteInteger(payload, ticket.localV);
        WriteInteger(payload, static_cast<std::uint8_t>(ticket.state));
        WriteInteger(payload, ticket.expiresAtTick);
    }
    WriteInteger(payload, static_cast<std::uint32_t>(attractors_.size()));
    for (const auto& attractor : attractors_) {
        WriteInteger(payload, attractor.cellId);
        WriteInteger(payload, attractor.strength);
        WriteInteger(payload, attractor.radiusInCells);
        WriteInteger(payload, attractor.expiresAtTick);
    }
    WriteInteger(payload, static_cast<std::uint32_t>(fulfilledRequestIds_.size()));
    for (const auto requestId : fulfilledRequestIds_) {
        WriteInteger(payload, requestId);
    }

    std::vector<std::byte> checkpoint;
    checkpoint.insert(checkpoint.end(), kCheckpointMagic.begin(), kCheckpointMagic.end());
    WriteInteger(checkpoint, kCheckpointFormatVersion);
    WriteInteger(checkpoint, graph_->revisionHash);
    WriteInteger(checkpoint, graph_->worldSeed);
    WriteInteger(checkpoint, ComputeWalkerConfigHash(config_));
    WriteInteger(checkpoint, static_cast<std::uint32_t>(payload.size()));
    WriteInteger(checkpoint, HashBytes(payload));
    checkpoint.insert(checkpoint.end(), payload.begin(), payload.end());
    return checkpoint;
}

bool WalkerSimulator::ImportCheckpoint(std::span<const std::byte> checkpoint, std::string* error) {
    if (!graph_) {
        SetError(error, "walker simulator is not initialized");
        return false;
    }
    constexpr std::size_t kHeaderSize = kCheckpointMagic.size() + sizeof(std::uint16_t) +
                                        sizeof(std::uint64_t) * 3 + sizeof(std::uint32_t) +
                                        sizeof(std::uint64_t);
    if (checkpoint.size() < kHeaderSize ||
        !std::equal(kCheckpointMagic.begin(), kCheckpointMagic.end(), checkpoint.begin())) {
        SetError(error, "checkpoint magic is invalid");
        return false;
    }

    std::size_t offset = kCheckpointMagic.size();
    std::uint16_t formatVersion = 0;
    std::uint64_t revisionHash = 0;
    std::uint64_t worldSeed = 0;
    std::uint64_t configHash = 0;
    std::uint32_t payloadSize = 0;
    std::uint64_t payloadHash = 0;
    if (!ReadInteger(checkpoint, offset, formatVersion) ||
        !ReadInteger(checkpoint, offset, revisionHash) ||
        !ReadInteger(checkpoint, offset, worldSeed) ||
        !ReadInteger(checkpoint, offset, configHash) ||
        !ReadInteger(checkpoint, offset, payloadSize) ||
        !ReadInteger(checkpoint, offset, payloadHash) ||
        formatVersion != kCheckpointFormatVersion || revisionHash != graph_->revisionHash ||
        worldSeed != graph_->worldSeed || configHash != ComputeWalkerConfigHash(config_) ||
        checkpoint.size() - offset != payloadSize) {
        SetError(error, "checkpoint metadata does not match the loaded world or config");
        return false;
    }

    const auto payload = checkpoint.subspan(offset);
    if (HashBytes(payload) != payloadHash) {
        SetError(error, "checkpoint payload checksum is invalid");
        return false;
    }

    std::size_t payloadOffset = 0;
    std::uint64_t restoredTick = 0;
    std::uint64_t restoredNextHordeId = 0;
    std::uint64_t restoredNextTicketId = 0;
    std::uint32_t cellCount = 0;
    if (!ReadInteger(payload, payloadOffset, restoredTick) ||
        !ReadInteger(payload, payloadOffset, restoredNextHordeId) ||
        !ReadInteger(payload, payloadOffset, restoredNextTicketId) ||
        !ReadInteger(payload, payloadOffset, cellCount) || cellCount != cellStates_.size()) {
        SetError(error, "checkpoint cell state is invalid");
        return false;
    }

    std::vector<CellState> restoredCellStates(cellCount);
    for (auto& cellState : restoredCellStates) {
        if (!ReadInteger(payload, payloadOffset, cellState.attraction) || cellState.attraction < 0) {
            SetError(error, "checkpoint attraction state is invalid");
            return false;
        }
    }

    std::uint32_t hordeCount = 0;
    if (!ReadInteger(payload, payloadOffset, hordeCount) || hordeCount > 65536) {
        SetError(error, "checkpoint horde count is invalid");
        return false;
    }
    std::vector<Horde> restoredHordes;
    restoredHordes.reserve(hordeCount);
    std::set<std::uint64_t> hordeIds;
    for (std::uint32_t index = 0; index < hordeCount; ++index) {
        Horde horde;
        if (!ReadInteger(payload, payloadOffset, horde.hordeId) ||
            !ReadInteger(payload, payloadOffset, horde.cellId) ||
            !ReadInteger(payload, payloadOffset, horde.nextCellId) ||
            !ReadInteger(payload, payloadOffset, horde.count) ||
            !ReadInteger(payload, payloadOffset, horde.reservedCount) ||
            !ReadInteger(payload, payloadOffset, horde.progressPermille) || horde.hordeId == 0 ||
            !hordeIds.insert(horde.hordeId).second || !CellIndex(horde.cellId) ||
            (horde.nextCellId != kInvalidCellId && !CellIndex(horde.nextCellId)) ||
            horde.reservedCount > horde.count || horde.progressPermille >= 1000) {
            SetError(error, "checkpoint horde state is invalid");
            return false;
        }
        restoredHordes.push_back(horde);
    }

    std::uint32_t ticketCount = 0;
    if (!ReadInteger(payload, payloadOffset, ticketCount) || ticketCount > 65536) {
        SetError(error, "checkpoint ticket count is invalid");
        return false;
    }
    std::map<std::uint64_t, Ticket> restoredTickets;
    for (std::uint32_t index = 0; index < ticketCount; ++index) {
        Ticket ticket;
        std::uint8_t state = 0;
        if (!ReadInteger(payload, payloadOffset, ticket.ticketId) ||
            !ReadInteger(payload, payloadOffset, ticket.hordeId) ||
            !ReadInteger(payload, payloadOffset, ticket.cellId) ||
            !ReadInteger(payload, payloadOffset, ticket.localU) ||
            !ReadInteger(payload, payloadOffset, ticket.localV) ||
            !ReadInteger(payload, payloadOffset, state) ||
            !ReadInteger(payload, payloadOffset, ticket.expiresAtTick) || ticket.ticketId == 0 ||
            state > static_cast<std::uint8_t>(TicketState::Despawned) || !hordeIds.contains(ticket.hordeId) ||
            !CellIndex(ticket.cellId) || !restoredTickets.emplace(ticket.ticketId, ticket).second) {
            SetError(error, "checkpoint ticket state is invalid");
            return false;
        }
        ticket.state = static_cast<TicketState>(state);
        restoredTickets[ticket.ticketId] = ticket;
    }

    std::uint32_t attractorCount = 0;
    if (!ReadInteger(payload, payloadOffset, attractorCount) || attractorCount > 65536) {
        SetError(error, "checkpoint attractor count is invalid");
        return false;
    }
    std::vector<Attractor> restoredAttractors;
    restoredAttractors.reserve(attractorCount);
    for (std::uint32_t index = 0; index < attractorCount; ++index) {
        Attractor attractor;
        if (!ReadInteger(payload, payloadOffset, attractor.cellId) ||
            !ReadInteger(payload, payloadOffset, attractor.strength) ||
            !ReadInteger(payload, payloadOffset, attractor.radiusInCells) ||
            !ReadInteger(payload, payloadOffset, attractor.expiresAtTick) || !CellIndex(attractor.cellId)) {
            SetError(error, "checkpoint attractor state is invalid");
            return false;
        }
        restoredAttractors.push_back(attractor);
    }

    std::uint32_t requestCount = 0;
    if (!ReadInteger(payload, payloadOffset, requestCount) || requestCount > 65536) {
        SetError(error, "checkpoint request state is invalid");
        return false;
    }
    std::vector<std::uint64_t> restoredRequests;
    restoredRequests.reserve(requestCount);
    for (std::uint32_t index = 0; index < requestCount; ++index) {
        std::uint64_t requestId = 0;
        if (!ReadInteger(payload, payloadOffset, requestId) || requestId == 0 ||
            (!restoredRequests.empty() && restoredRequests.back() >= requestId)) {
            SetError(error, "checkpoint request ids are invalid");
            return false;
        }
        restoredRequests.push_back(requestId);
    }
    if (payloadOffset != payload.size()) {
        SetError(error, "checkpoint has trailing data");
        return false;
    }

    tick_ = restoredTick;
    nextHordeId_ = restoredNextHordeId;
    nextTicketId_ = restoredNextTicketId;
    cellStates_ = std::move(restoredCellStates);
    hordes_ = std::move(restoredHordes);
    tickets_ = std::move(restoredTickets);
    attractors_ = std::move(restoredAttractors);
    fulfilledRequestIds_ = std::move(restoredRequests);
    pendingCommands_.clear();
    PublishSnapshot();
    return true;
}

}  // namespace zombiesim::walker