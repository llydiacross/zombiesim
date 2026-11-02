#include "GarrysMod/Lua/Interface.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <type_traits>
#include <vector>

#include "zombiesim_walker/walker_config.hpp"
#include "zombiesim_walker/world_graph.hpp"

#include "walker_worker.hpp"

using namespace GarrysMod::Lua;

namespace {

constexpr double kWalkerApiVersion = 3.0;
constexpr std::size_t kMaximumCheckpointBytes = 8U * 1024U * 1024U;
std::unique_ptr<zombiesim::walker::gmod::WalkerWorker> worker;

static_assert(sizeof(void*) == 8);
static_assert(offsetof(lua_State, luabase) == 120);

int PushFailure(ILuaBase* lua, const std::string& error) {
    lua->PushBool(false);
    lua->PushString(error.c_str());
    return 2;
}

bool ReadUnsigned(ILuaBase* lua, int index, std::uint64_t maximum, std::uint64_t& value, std::string& error) {
    if (!lua->IsType(index, Type::Number)) {
        error = "expected a numeric argument";
        return false;
    }
    const auto number = lua->GetNumber(index);
    if (!std::isfinite(number) || number < 0 || std::floor(number) != number ||
        number > static_cast<double>(maximum)) {
        error = "numeric argument is outside the supported range";
        return false;
    }
    value = static_cast<std::uint64_t>(number);
    return true;
}

bool ReadIdPair(ILuaBase* lua, int lowIndex, int highIndex, std::uint64_t& value, std::string& error) {
    std::uint64_t low = 0;
    std::uint64_t high = 0;
    if (!ReadUnsigned(lua, lowIndex, std::numeric_limits<std::uint32_t>::max(), low, error) ||
        !ReadUnsigned(lua, highIndex, std::numeric_limits<std::uint32_t>::max(), high, error)) {
        return false;
    }
    value = low | (high << 32U);
    return value != 0;
}

void PushIdPair(ILuaBase* lua, std::uint64_t value, const char* lowName, const char* highName) {
    lua->PushNumber(static_cast<double>(static_cast<std::uint32_t>(value)));
    lua->SetField(-2, lowName);
    lua->PushNumber(static_cast<double>(value >> 32U));
    lua->SetField(-2, highName);
}

const char* TicketStateName(zombiesim::walker::TicketState state) {
    switch (state) {
        case zombiesim::walker::TicketState::Reserved:
            return "reserved";
        case zombiesim::walker::TicketState::Materialized:
            return "materialized";
        case zombiesim::walker::TicketState::Rejected:
            return "rejected";
        case zombiesim::walker::TicketState::Expired:
            return "expired";
        case zombiesim::walker::TicketState::Killed:
            return "killed";
        case zombiesim::walker::TicketState::Despawned:
            return "despawned";
    }
    return "unknown";
}

bool ReadConfig(ILuaBase* lua, zombiesim::walker::WalkerConfig& config, std::string& error) {
    if (lua->Top() < 3 || lua->IsType(3, Type::Nil)) {
        return true;
    }
    if (!lua->IsType(3, Type::Table)) {
        error = "walker config must be a table";
        return false;
    }

    const auto readField = [lua, &error](const char* name, std::uint64_t minimum, std::uint64_t maximum, auto& value) {
        lua->GetField(3, name);
        if (lua->IsType(-1, Type::Nil)) {
            lua->Pop();
            return true;
        }
        std::uint64_t parsed = 0;
        const auto valid = ReadUnsigned(lua, -1, maximum, parsed, error) && parsed >= minimum;
        lua->Pop();
        if (!valid) {
            error = std::string("invalid config field: ") + name;
            return false;
        }
        value = static_cast<std::remove_reference_t<decltype(value)>>(parsed);
        return true;
    };

    return readField("minimumGroupSize", 1, std::numeric_limits<std::uint16_t>::max(), config.minimumGroupSize) &&
           readField("maximumGroupSize", 1, std::numeric_limits<std::uint16_t>::max(), config.maximumGroupSize) &&
           readField("progressPerTick", 1, 1000, config.progressPerTick) &&
           readField("attractionDecayPermille", 0, 1000, config.attractionDecayPermille) &&
           readField("safeZonePenalty", 0, std::numeric_limits<std::int32_t>::max(), config.safeZonePenalty) &&
           readField("ticketLifetimeTicks", 1, std::numeric_limits<std::uint16_t>::max(), config.ticketLifetimeTicks) &&
           readField("maximumTicketsPerRequest", 1, std::numeric_limits<std::uint16_t>::max(), config.maximumTicketsPerRequest) &&
           zombiesim::walker::ValidateWalkerConfig(config, &error);
}

void PushStats(ILuaBase* lua, const zombiesim::walker::gmod::WorkerStats& stats) {
    lua->CreateTable();
    lua->PushString(zombiesim::walker::gmod::WorkerLifecycleName(stats.lifecycle));
    lua->SetField(-2, "Lifecycle");
    lua->PushString(stats.profileId.c_str());
    lua->SetField(-2, "ProfileId");
    lua->PushString(stats.lastError.c_str());
    lua->SetField(-2, "LastError");
    lua->PushString(std::to_string(stats.graphRevisionHash).c_str());
    lua->SetField(-2, "GraphRevisionHash");
    lua->PushString(std::to_string(stats.stateHash).c_str());
    lua->SetField(-2, "StateHash");
    lua->PushString(std::to_string(stats.tick).c_str());
    lua->SetField(-2, "Tick");
    lua->PushString(std::to_string(stats.totalPopulation).c_str());
    lua->SetField(-2, "TotalPopulation");
    lua->PushString(std::to_string(stats.droppedTickCount).c_str());
    lua->SetField(-2, "DroppedTickCount");
    lua->PushString(std::to_string(stats.apiErrorCount).c_str());
    lua->SetField(-2, "ApiErrorCount");
    lua->PushString(std::to_string(stats.acceptedCommandCount).c_str());
    lua->SetField(-2, "AcceptedCommandCount");
    lua->PushString(std::to_string(stats.lastAcceptedCommandTick).c_str());
    lua->SetField(-2, "LastAcceptedCommandTick");
    lua->PushNumber(stats.averageTickMicroseconds);
    lua->SetField(-2, "AverageTickMicroseconds");
    lua->PushNumber(stats.maximumTickMicroseconds);
    lua->SetField(-2, "MaximumTickMicroseconds");
    if (stats.activeCellId == zombiesim::walker::kInvalidCellId) {
        lua->PushNil();
    } else {
        lua->PushNumber(stats.activeCellId);
    }
    lua->SetField(-2, "ActiveCellId");
    lua->PushString(std::to_string(stats.hordeCount).c_str());
    lua->SetField(-2, "HordeCount");
    lua->PushString(std::to_string(stats.ticketCount).c_str());
    lua->SetField(-2, "TicketCount");
    lua->PushString(std::to_string(stats.pendingCommandCount).c_str());
    lua->SetField(-2, "PendingCommandCount");
}

LUA_FUNCTION(GetInfo) {
    LUA->CreateTable();
    LUA->PushNumber(kWalkerApiVersion);
    LUA->SetField(-2, "ApiVersion");
    LUA->PushString("walker_core");
    LUA->SetField(-2, "Core");
    LUA->PushString("phase-2-worker");
    LUA->SetField(-2, "Status");
    return 1;
}

LUA_FUNCTION(RunSelfTest) {
    const zombiesim::walker::WalkerConfig config;
    std::string error;
    const auto valid = zombiesim::walker::ValidateWalkerConfig(config, &error) &&
                       zombiesim::walker::ComputeWalkerConfigHash(config) != 0;
    LUA->PushBool(valid);
    if (!valid) {
        LUA->PushString(error.c_str());
        return 2;
    }
    return 1;
}

LUA_FUNCTION(LoadWorldJson) {
    if (!LUA->IsType(1, Type::String) || !LUA->IsType(2, Type::String)) {
        return PushFailure(LUA, "LoadWorldJson expects JSON bytes and a profile id");
    }

    unsigned int jsonLength = 0;
    unsigned int profileLength = 0;
    const auto* json = LUA->GetString(1, &jsonLength);
    const auto* profile = LUA->GetString(2, &profileLength);
    if (json == nullptr || profile == nullptr || jsonLength == 0 || profileLength == 0 || profileLength > 64) {
        return PushFailure(LUA, "LoadWorldJson received invalid JSON bytes or profile id");
    }

    zombiesim::walker::WalkerConfig config;
    std::string error;
    if (!ReadConfig(LUA, config, error)) {
        return PushFailure(LUA, error);
    }

    std::vector<std::byte> jsonBytes;
    jsonBytes.reserve(jsonLength);
    for (unsigned int index = 0; index < jsonLength; ++index) {
        jsonBytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(json[index])));
    }
    if (!worker->LoadWorldJson(jsonBytes, std::string_view(profile, profileLength), config, &error)) {
        return PushFailure(LUA, error);
    }

    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(Start) {
    std::string error;
    if (!worker->Start(&error)) {
        return PushFailure(LUA, error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(Stop) {
    worker->Stop();
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(ExportCheckpoint) {
    std::vector<std::byte> checkpoint;
    std::string error;
    if (!worker->ExportCheckpoint(checkpoint, &error)) {
        return PushFailure(LUA, error);
    }
    if (checkpoint.empty() || checkpoint.size() > kMaximumCheckpointBytes) {
        return PushFailure(LUA, "walker checkpoint size is outside the supported range");
    }

    LUA->PushString(
        reinterpret_cast<const char*>(checkpoint.data()),
        static_cast<unsigned int>(checkpoint.size()));
    return 1;
}

LUA_FUNCTION(ImportCheckpoint) {
    if (!LUA->IsType(1, Type::String)) {
        return PushFailure(LUA, "ImportCheckpoint expects checkpoint bytes");
    }

    unsigned int checkpointLength = 0;
    const auto* checkpoint = LUA->GetString(1, &checkpointLength);
    if (checkpoint == nullptr || checkpointLength == 0 || checkpointLength > kMaximumCheckpointBytes) {
        return PushFailure(LUA, "walker checkpoint size is outside the supported range");
    }

    std::vector<std::byte> checkpointBytes;
    checkpointBytes.reserve(checkpointLength);
    for (unsigned int index = 0; index < checkpointLength; ++index) {
        checkpointBytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(checkpoint[index])));
    }

    std::string error;
    if (!worker->ImportCheckpoint(checkpointBytes, &error)) {
        return PushFailure(LUA, error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(RequestCheckpointExport) {
    std::string error;
    if (!worker->RequestCheckpointExport(&error)) {
        return PushFailure(LUA, error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(TakeCheckpointExport) {
    std::vector<std::byte> checkpoint;
    std::string error;
    if (!worker->TakeCheckpointExport(checkpoint, &error)) {
        LUA->PushNil();
        LUA->PushString(error.c_str());
        return 2;
    }
    LUA->PushString(
        reinterpret_cast<const char*>(checkpoint.data()),
        static_cast<unsigned int>(checkpoint.size()));
    return 1;
}

LUA_FUNCTION(SetActiveCell) {
    std::uint64_t cellId = 0;
    std::string error;
    if (!ReadUnsigned(LUA, 1, std::numeric_limits<std::uint16_t>::max(), cellId, error) ||
        !worker->SetActiveCell(static_cast<std::uint16_t>(cellId), &error)) {
        return PushFailure(LUA, error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(SubmitAttractor) {
    std::uint64_t cellId = 0;
    std::uint64_t localU = 0;
    std::uint64_t localV = 0;
    std::uint64_t strength = 0;
    std::uint64_t radius = 0;
    std::uint64_t duration = 0;
    std::string error;
    if (!ReadUnsigned(LUA, 1, std::numeric_limits<std::uint16_t>::max(), cellId, error) ||
        !ReadUnsigned(LUA, 2, std::numeric_limits<std::uint16_t>::max(), localU, error) ||
        !ReadUnsigned(LUA, 3, std::numeric_limits<std::uint16_t>::max(), localV, error) ||
        !ReadUnsigned(LUA, 4, std::numeric_limits<std::uint16_t>::max(), strength, error) ||
        !ReadUnsigned(LUA, 5, std::numeric_limits<std::uint16_t>::max(), radius, error) ||
        !ReadUnsigned(LUA, 6, std::numeric_limits<std::uint16_t>::max(), duration, error) ||
        !LUA->IsType(7, Type::String)) {
        return PushFailure(LUA, "SubmitAttractor received invalid arguments");
    }
    static_cast<void>(localU);
    static_cast<void>(localV);
    if (!worker->Submit(
            zombiesim::walker::NoiseCommand{
                .cellId = static_cast<std::uint16_t>(cellId),
                .strength = static_cast<std::uint16_t>(strength),
                .radiusInCells = static_cast<std::uint16_t>(radius),
                .durationTicks = static_cast<std::uint16_t>(duration),
            },
            &error)) {
        return PushFailure(LUA, error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(GetStats) {
    PushStats(LUA, worker->GetStats());
    return 1;
}

LUA_FUNCTION(GetCellSummary) {
    std::uint64_t cellId = 0;
    std::string error;
    if (!ReadUnsigned(LUA, 1, std::numeric_limits<std::uint16_t>::max(), cellId, error)) {
        return PushFailure(LUA, error);
    }
    const auto summary = worker->GetCellSummary(static_cast<std::uint16_t>(cellId));
    if (!summary) {
        LUA->PushNil();
        return 1;
    }

    LUA->CreateTable();
    LUA->PushNumber(summary->cellId);
    LUA->SetField(-2, "CellId");
    LUA->PushString(std::to_string(summary->ambientPopulation).c_str());
    LUA->SetField(-2, "AmbientPopulation");
    LUA->PushString(std::to_string(summary->reservedPopulation).c_str());
    LUA->SetField(-2, "ReservedPopulation");
    LUA->PushString(std::to_string(summary->materializedPopulation).c_str());
    LUA->SetField(-2, "MaterializedPopulation");
    LUA->PushNumber(summary->attraction);
    LUA->SetField(-2, "Attraction");
    return 1;
}

LUA_FUNCTION(GetHordeSummaries) {
    const auto hordes = worker->GetHordeSummaries();
    if (hordes.size() > 8191) {
        return PushFailure(LUA, "horde summary count exceeds the preview transport limit");
    }

    LUA->CreateTable();
    for (std::size_t index = 0; index < hordes.size(); ++index) {
        const auto& horde = hordes[index];
        LUA->PushNumber(static_cast<double>(index + 1));
        LUA->CreateTable();
        LUA->PushNumber(static_cast<double>(static_cast<std::uint32_t>(horde.hordeId)));
        LUA->SetField(-2, "HordeIdLow");
        LUA->PushNumber(static_cast<double>(horde.hordeId >> 32U));
        LUA->SetField(-2, "HordeIdHigh");
        LUA->PushNumber(static_cast<double>(horde.cellId));
        LUA->SetField(-2, "CellId");
        LUA->PushNumber(static_cast<double>(horde.nextCellId));
        LUA->SetField(-2, "NextCellId");
        LUA->PushNumber(static_cast<double>(horde.count));
        LUA->SetField(-2, "Count");
        LUA->PushNumber(static_cast<double>(horde.progressPermille));
        LUA->SetField(-2, "ProgressPermille");
        LUA->SetTable(-3);
    }
    return 1;
}

LUA_FUNCTION(RequestSpawnTickets) {
    std::uint64_t cellId = 0;
    std::uint64_t maximumCount = 0;
    std::uint64_t requestId = 0;
    std::string error;
    if (!ReadUnsigned(LUA, 1, std::numeric_limits<std::uint16_t>::max(), cellId, error) ||
        !ReadUnsigned(LUA, 2, std::numeric_limits<std::uint16_t>::max(), maximumCount, error) ||
        !ReadIdPair(LUA, 3, 4, requestId, error) ||
        !worker->Submit(
            zombiesim::walker::RequestSpawnTicketsCommand{
                .cellId = static_cast<std::uint16_t>(cellId),
                .maximumCount = static_cast<std::uint16_t>(maximumCount),
                .requestId = requestId,
            },
            &error)) {
        return PushFailure(LUA, error.empty() ? "RequestSpawnTickets received invalid arguments" : error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(AcknowledgeTicket) {
    std::uint64_t ticketId = 0;
    std::string error;
    if (!ReadIdPair(LUA, 1, 2, ticketId, error) ||
        !worker->Submit(zombiesim::walker::AcknowledgeTicketCommand{.ticketId = ticketId}, &error)) {
        return PushFailure(LUA, error.empty() ? "AcknowledgeTicket received invalid arguments" : error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(RejectTicket) {
    std::uint64_t ticketId = 0;
    std::string error;
    if (!ReadIdPair(LUA, 1, 2, ticketId, error) ||
        !worker->Submit(zombiesim::walker::RejectTicketCommand{.ticketId = ticketId}, &error)) {
        return PushFailure(LUA, error.empty() ? "RejectTicket received invalid arguments" : error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(ResolveTicket) {
    std::uint64_t ticketId = 0;
    std::string error;
    if (!ReadIdPair(LUA, 1, 2, ticketId, error) || !LUA->IsType(3, Type::Bool) ||
        !worker->Submit(
            zombiesim::walker::ResolveTicketCommand{
                .ticketId = ticketId,
                .killed = LUA->GetBool(3),
            },
            &error)) {
        return PushFailure(LUA, error.empty() ? "ResolveTicket received invalid arguments" : error);
    }
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(GetTicketSummaries) {
    const auto tickets = worker->GetTicketSummaries();
    LUA->CreateTable();
    for (std::size_t index = 0; index < tickets.size(); ++index) {
        const auto& ticket = tickets[index];
        LUA->PushNumber(static_cast<double>(index + 1));
        LUA->CreateTable();
        PushIdPair(LUA, ticket.ticketId, "TicketIdLow", "TicketIdHigh");
        PushIdPair(LUA, ticket.hordeId, "HordeIdLow", "HordeIdHigh");
        LUA->PushNumber(static_cast<double>(ticket.cellId));
        LUA->SetField(-2, "CellId");
        LUA->PushNumber(static_cast<double>(ticket.localU));
        LUA->SetField(-2, "LocalU");
        LUA->PushNumber(static_cast<double>(ticket.localV));
        LUA->SetField(-2, "LocalV");
        LUA->PushString(TicketStateName(ticket.state));
        LUA->SetField(-2, "State");
        LUA->PushString(std::to_string(ticket.expiresAtTick).c_str());
        LUA->SetField(-2, "ExpiresAtTick");
        LUA->SetTable(-3);
    }
    return 1;
}

}  // namespace

GMOD_MODULE_OPEN() {
    worker = std::make_unique<zombiesim::walker::gmod::WalkerWorker>();
    LUA->PushSpecial(SPECIAL_GLOB);
    LUA->CreateTable();
    LUA->PushNumber(kWalkerApiVersion);
    LUA->SetField(-2, "ApiVersion");
    LUA->PushCFunction(GetInfo);
    LUA->SetField(-2, "GetInfo");
    LUA->PushCFunction(RunSelfTest);
    LUA->SetField(-2, "RunSelfTest");
    LUA->PushCFunction(LoadWorldJson);
    LUA->SetField(-2, "LoadWorldJson");
    LUA->PushCFunction(Start);
    LUA->SetField(-2, "Start");
    LUA->PushCFunction(Stop);
    LUA->SetField(-2, "Stop");
    LUA->PushCFunction(ExportCheckpoint);
    LUA->SetField(-2, "ExportCheckpoint");
    LUA->PushCFunction(ImportCheckpoint);
    LUA->SetField(-2, "ImportCheckpoint");
    LUA->PushCFunction(RequestCheckpointExport);
    LUA->SetField(-2, "RequestCheckpointExport");
    LUA->PushCFunction(TakeCheckpointExport);
    LUA->SetField(-2, "TakeCheckpointExport");
    LUA->PushCFunction(SetActiveCell);
    LUA->SetField(-2, "SetActiveCell");
    LUA->PushCFunction(SubmitAttractor);
    LUA->SetField(-2, "SubmitAttractor");
    LUA->PushCFunction(GetStats);
    LUA->SetField(-2, "GetStats");
    LUA->PushCFunction(GetCellSummary);
    LUA->SetField(-2, "GetCellSummary");
    LUA->PushCFunction(GetHordeSummaries);
    LUA->SetField(-2, "GetHordeSummaries");
    LUA->PushCFunction(RequestSpawnTickets);
    LUA->SetField(-2, "RequestSpawnTickets");
    LUA->PushCFunction(AcknowledgeTicket);
    LUA->SetField(-2, "AcknowledgeTicket");
    LUA->PushCFunction(RejectTicket);
    LUA->SetField(-2, "RejectTicket");
    LUA->PushCFunction(ResolveTicket);
    LUA->SetField(-2, "ResolveTicket");
    LUA->PushCFunction(GetTicketSummaries);
    LUA->SetField(-2, "GetTicketSummaries");
    LUA->SetField(-2, "ZM_WalkerNative");
    LUA->Pop(1);
    return 0;
}

GMOD_MODULE_CLOSE() {
    worker.reset();
    return 0;
}