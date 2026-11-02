#pragma once

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <thread>

#include "zombiesim_walker/command_types.hpp"
#include "zombiesim_walker/walker_config.hpp"
#include "zombiesim_walker/walker_simulator.hpp"

namespace zombiesim::walker::gmod {

enum class WorkerLifecycle : std::uint8_t {
    Unloaded,
    GraphReady,
    Running,
    Stopping,
    Faulted,
};

[[nodiscard]] const char* WorkerLifecycleName(WorkerLifecycle lifecycle);

struct WorkerStats {
    WorkerLifecycle lifecycle = WorkerLifecycle::Unloaded;
    std::string profileId;
    std::string lastError;
    std::uint64_t graphRevisionHash = 0;
    std::uint64_t stateHash = 0;
    std::uint64_t tick = 0;
    std::uint64_t totalPopulation = 0;
    std::uint64_t droppedTickCount = 0;
    std::uint64_t apiErrorCount = 0;
    std::uint64_t acceptedCommandCount = 0;
    std::uint64_t lastAcceptedCommandTick = 0;
    std::uint32_t averageTickMicroseconds = 0;
    std::uint32_t maximumTickMicroseconds = 0;
    std::uint16_t activeCellId = kInvalidCellId;
    std::size_t hordeCount = 0;
    std::size_t ticketCount = 0;
    std::size_t pendingCommandCount = 0;
};

class WalkerWorker final {
public:
    WalkerWorker() = default;
    ~WalkerWorker();

    WalkerWorker(const WalkerWorker&) = delete;
    WalkerWorker& operator=(const WalkerWorker&) = delete;

    [[nodiscard]] bool LoadWorldJson(
        std::span<const std::byte> jsonBytes,
        std::string_view profileId,
        const WalkerConfig& config,
        std::string* error = nullptr);
    [[nodiscard]] bool Start(std::string* error = nullptr);
    void Stop();
    [[nodiscard]] bool ExportCheckpoint(std::vector<std::byte>& checkpoint, std::string* error = nullptr);
    [[nodiscard]] bool RequestCheckpointExport(std::string* error = nullptr);
    [[nodiscard]] bool TakeCheckpointExport(std::vector<std::byte>& checkpoint, std::string* error = nullptr);
    [[nodiscard]] bool ImportCheckpoint(std::span<const std::byte> checkpoint, std::string* error = nullptr);
    [[nodiscard]] bool Submit(WalkerCommand command, std::string* error = nullptr);
    [[nodiscard]] bool SetActiveCell(std::uint16_t cellId, std::string* error = nullptr);
    [[nodiscard]] std::optional<CellSummary> GetCellSummary(std::uint16_t cellId) const;
    [[nodiscard]] std::vector<HordeSummary> GetHordeSummaries() const;
    [[nodiscard]] std::vector<TicketSummary> GetTicketSummaries() const;
    [[nodiscard]] WorkerStats GetStats() const;

private:
    void Run();
    void PublishSnapshot(
        const OutputSnapshot& snapshot,
        std::uint32_t tickMicroseconds,
        std::uint32_t acceptedCommandCount);
    void SetFault(std::string error);

    static constexpr std::size_t kMaximumPendingCommands = 1024;

    mutable std::mutex mutex_;
    std::condition_variable wakeWorker_;
    std::thread thread_;
    std::optional<WalkerSimulator> simulator_;
    OutputSnapshot snapshot_;
    std::deque<WalkerCommand> pendingCommands_;
    WorkerLifecycle lifecycle_ = WorkerLifecycle::Unloaded;
    std::string profileId_;
    std::string lastError_;
    std::uint64_t droppedTickCount_ = 0;
    std::uint64_t apiErrorCount_ = 0;
    std::uint64_t acceptedCommandCount_ = 0;
    std::uint64_t lastAcceptedCommandTick_ = 0;
    std::uint64_t totalTickMicroseconds_ = 0;
    std::uint64_t completedTickCount_ = 0;
    std::uint32_t maximumTickMicroseconds_ = 0;
    std::uint16_t activeCellId_ = kInvalidCellId;
    bool stopRequested_ = false;
    std::uint64_t requestedCheckpointSequence_ = 0;
    std::uint64_t completedCheckpointSequence_ = 0;
    std::vector<std::byte> checkpointResult_;
    std::string checkpointError_;
    bool checkpointResultAvailable_ = false;
};

}  // namespace zombiesim::walker::gmod