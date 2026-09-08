#pragma once

#include <cstdint>
#include <variant>

namespace zombiesim::walker {

enum class TicketState : std::uint8_t {
    Reserved,
    Materialized,
    Rejected,
    Expired,
    Killed,
    Despawned,
};

struct NoiseCommand {
    std::uint16_t cellId = 0;
    std::uint16_t strength = 0;
    std::uint16_t radiusInCells = 0;
    std::uint16_t durationTicks = 0;
};

struct RequestSpawnTicketsCommand {
    std::uint16_t cellId = 0;
    std::uint16_t maximumCount = 0;
    std::uint64_t requestId = 0;
};

struct AcknowledgeTicketCommand {
    std::uint64_t ticketId = 0;
};

struct RejectTicketCommand {
    std::uint64_t ticketId = 0;
};

struct ResolveTicketCommand {
    std::uint64_t ticketId = 0;
    bool killed = false;
};

using WalkerCommand = std::variant<
    NoiseCommand,
    RequestSpawnTicketsCommand,
    AcknowledgeTicketCommand,
    RejectTicketCommand,
    ResolveTicketCommand>;

}  // namespace zombiesim::walker