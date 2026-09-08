#include "walker_worker.hpp"

#include <algorithm>
#include <chrono>
#include <exception>
#include <utility>

#include "zombiesim_walker/world_json_importer.hpp"

namespace zombiesim::walker::gmod {
namespace {

constexpr auto kTickInterval = std::chrono::milliseconds(250);
constexpr auto kMaximumCatchUp = std::chrono::seconds(1);

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

}  // namespace

const char* WorkerLifecycleName(WorkerLifecycle lifecycle) {
    switch (lifecycle) {
        case WorkerLifecycle::Unloaded:
            return "unloaded";
        case WorkerLifecycle::GraphReady:
            return "graph-ready";
        case WorkerLifecycle::Running:
            return "running";
        case WorkerLifecycle::Stopping:
            return "stopping";
        case WorkerLifecycle::Faulted:
            return "faulted";
    }
    return "unknown";
}

WalkerWorker::~WalkerWorker() {
    Stop();
}

bool WalkerWorker::LoadWorldJson(
    std::span<const std::byte> jsonBytes,
    std::string_view profileId,
    const WalkerConfig& config,
    std::string* error) {
    Stop();

    const auto world = zombiesim::walker::LoadWorldJson(jsonBytes, profileId);
    if (!world) {
        SetError(error, world.error);
        return false;
    }

    WalkerSimulator simulator;
    std::string initializeError;
    if (!simulator.Initialize(*world.graph, config, &initializeError)) {
        SetError(error, initializeError);
        return false;
    }

    std::scoped_lock lock(mutex_);
    simulator_ = std::move(simulator);
    snapshot_ = simulator_->Snapshot();
    pendingCommands_.clear();
    profileId_ = std::string(profileId);
    lastError_.clear();
    droppedTickCount_ = 0;
    apiErrorCount_ = 0;
    acceptedCommandCount_ = 0;
    lastAcceptedCommandTick_ = 0;
    totalTickMicroseconds_ = 0;
    completedTickCount_ = 0;
    maximumTickMicroseconds_ = 0;
    activeCellId_ = kInvalidCellId;
    stopRequested_ = false;
    lifecycle_ = WorkerLifecycle::GraphReady;
    return true;
}

bool WalkerWorker::Start(std::string* error) {
    std::scoped_lock lock(mutex_);
    if (!simulator_) {
        SetError(error, "world JSON must load before the worker starts");
        return false;
    }
    if (lifecycle_ == WorkerLifecycle::Running) {
        return true;
    }
    if (thread_.joinable()) {
        SetError(error, "worker thread is still stopping");
        return false;
    }

    stopRequested_ = false;
    lifecycle_ = WorkerLifecycle::Running;
    thread_ = std::thread(&WalkerWorker::Run, this);
    return true;
}

void WalkerWorker::Stop() {
    std::thread thread;
    {
        std::scoped_lock lock(mutex_);
        if (thread_.joinable()) {
            lifecycle_ = WorkerLifecycle::Stopping;
            stopRequested_ = true;
            wakeWorker_.notify_all();
            thread = std::move(thread_);
        } else if (simulator_ && lifecycle_ != WorkerLifecycle::Faulted) {
            lifecycle_ = WorkerLifecycle::GraphReady;
        }
    }

    if (thread.joinable()) {
        thread.join();
    }

    std::scoped_lock lock(mutex_);
    if (simulator_ && lifecycle_ != WorkerLifecycle::Faulted) {
        lifecycle_ = WorkerLifecycle::GraphReady;
    }
}

bool WalkerWorker::Submit(WalkerCommand command, std::string* error) {
    std::scoped_lock lock(mutex_);
    if (lifecycle_ != WorkerLifecycle::Running) {
        SetError(error, "walker worker is not running");
        return false;
    }
    if (pendingCommands_.size() >= kMaximumPendingCommands) {
        ++apiErrorCount_;
        SetError(error, "walker command queue is full");
        return false;
    }

    pendingCommands_.push_back(std::move(command));
    wakeWorker_.notify_one();
    return true;
}

bool WalkerWorker::SetActiveCell(std::uint16_t cellId, std::string* error) {
    std::scoped_lock lock(mutex_);
    const auto cell = std::find_if(
        snapshot_.cells.begin(),
        snapshot_.cells.end(),
        [cellId](const CellSummary& summary) { return summary.cellId == cellId; });
    if (cell == snapshot_.cells.end()) {
        SetError(error, "active cell is not part of the loaded world");
        return false;
    }

    activeCellId_ = cellId;
    return true;
}

std::optional<CellSummary> WalkerWorker::GetCellSummary(std::uint16_t cellId) const {
    std::scoped_lock lock(mutex_);
    const auto cell = std::find_if(
        snapshot_.cells.begin(),
        snapshot_.cells.end(),
        [cellId](const CellSummary& summary) { return summary.cellId == cellId; });
    return cell == snapshot_.cells.end() ? std::nullopt : std::optional<CellSummary>(*cell);
}

std::vector<HordeSummary> WalkerWorker::GetHordeSummaries() const {
    std::scoped_lock lock(mutex_);
    return snapshot_.hordes;
}

WorkerStats WalkerWorker::GetStats() const {
    std::scoped_lock lock(mutex_);
    WorkerStats stats;
    stats.lifecycle = lifecycle_;
    stats.profileId = profileId_;
    stats.lastError = lastError_;
    stats.graphRevisionHash = snapshot_.graphRevisionHash;
    stats.stateHash = snapshot_.stateHash;
    stats.tick = snapshot_.tick;
    stats.totalPopulation = snapshot_.totalPopulation;
    stats.droppedTickCount = droppedTickCount_;
    stats.apiErrorCount = apiErrorCount_;
    stats.acceptedCommandCount = acceptedCommandCount_;
    stats.lastAcceptedCommandTick = lastAcceptedCommandTick_;
    stats.averageTickMicroseconds = completedTickCount_ == 0
        ? 0
        : static_cast<std::uint32_t>(totalTickMicroseconds_ / completedTickCount_);
    stats.maximumTickMicroseconds = maximumTickMicroseconds_;
    stats.activeCellId = activeCellId_;
    stats.hordeCount = snapshot_.hordes.size();
    stats.ticketCount = snapshot_.tickets.size();
    stats.pendingCommandCount = pendingCommands_.size();
    return stats;
}

void WalkerWorker::Run() {
    auto nextTickAt = std::chrono::steady_clock::now() + kTickInterval;
    try {
        while (true) {
            std::deque<WalkerCommand> commands;
            {
                std::unique_lock lock(mutex_);
                wakeWorker_.wait_until(lock, nextTickAt, [this] { return stopRequested_; });
                if (stopRequested_) {
                    return;
                }
                commands.swap(pendingCommands_);
            }

            const auto startedAt = std::chrono::steady_clock::now();
            std::uint32_t acceptedCommandCount = 0;
            for (auto& command : commands) {
                std::string commandError;
                if (!simulator_->Submit(std::move(command), &commandError)) {
                    std::scoped_lock lock(mutex_);
                    ++apiErrorCount_;
                    lastError_ = commandError;
                } else {
                    ++acceptedCommandCount;
                }
            }
            const auto snapshot = simulator_->AdvanceOneTick();
            const auto completedAt = std::chrono::steady_clock::now();
            const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(completedAt - startedAt);
            PublishSnapshot(
                snapshot,
                static_cast<std::uint32_t>(elapsed.count()),
                acceptedCommandCount);

            nextTickAt += kTickInterval;
            if (completedAt - nextTickAt > kMaximumCatchUp) {
                std::scoped_lock lock(mutex_);
                ++droppedTickCount_;
                nextTickAt = completedAt + kTickInterval;
            }
        }
    } catch (const std::exception& exception) {
        SetFault(exception.what());
    } catch (...) {
        SetFault("walker worker encountered an unknown exception");
    }
}

void WalkerWorker::PublishSnapshot(
    const OutputSnapshot& snapshot,
    std::uint32_t tickMicroseconds,
    std::uint32_t acceptedCommandCount) {
    std::scoped_lock lock(mutex_);
    snapshot_ = snapshot;
    totalTickMicroseconds_ += tickMicroseconds;
    ++completedTickCount_;
    maximumTickMicroseconds_ = std::max(maximumTickMicroseconds_, tickMicroseconds);
    acceptedCommandCount_ += acceptedCommandCount;
    if (acceptedCommandCount > 0) {
        lastAcceptedCommandTick_ = snapshot.tick;
    }
}

void WalkerWorker::SetFault(std::string error) {
    std::scoped_lock lock(mutex_);
    lifecycle_ = WorkerLifecycle::Faulted;
    lastError_ = std::move(error);
    stopRequested_ = true;
    wakeWorker_.notify_all();
}

}  // namespace zombiesim::walker::gmod