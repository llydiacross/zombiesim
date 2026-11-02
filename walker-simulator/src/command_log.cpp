#include "zombiesim_walker/command_log.hpp"

#include <exception>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

namespace zombiesim::walker {
namespace {

using Json = nlohmann::json;

[[nodiscard]] std::uint64_t ReadUnsigned(
    const Json& entry,
    const char* fieldName,
    std::uint64_t maximum) {
    const auto& value = entry.at(fieldName);
    std::uint64_t number = 0;
    if (value.is_number_unsigned()) {
        number = value.get<std::uint64_t>();
    } else if (value.is_number_integer()) {
        const auto signedNumber = value.get<std::int64_t>();
        if (signedNumber < 0) {
            throw std::runtime_error(std::string(fieldName) + " is out of range");
        }
        number = static_cast<std::uint64_t>(signedNumber);
    } else {
        throw std::runtime_error(std::string(fieldName) + " must be an integer");
    }
    if (number > maximum) {
        throw std::runtime_error(std::string(fieldName) + " is out of range");
    }
    return number;
}

[[nodiscard]] WalkerCommand ParseCommand(const Json& entry) {
    const auto type = entry.at("type").get<std::string>();
    if (type == "noise") {
        return NoiseCommand{
            .cellId = static_cast<std::uint16_t>(ReadUnsigned(entry, "cellId", std::numeric_limits<std::uint16_t>::max())),
            .strength = static_cast<std::uint16_t>(ReadUnsigned(entry, "strength", std::numeric_limits<std::uint16_t>::max())),
            .radiusInCells = static_cast<std::uint16_t>(ReadUnsigned(entry, "radiusInCells", std::numeric_limits<std::uint16_t>::max())),
            .durationTicks = static_cast<std::uint16_t>(ReadUnsigned(entry, "durationTicks", std::numeric_limits<std::uint16_t>::max())),
        };
    }
    if (type == "request_tickets") {
        return RequestSpawnTicketsCommand{
            .cellId = static_cast<std::uint16_t>(ReadUnsigned(entry, "cellId", std::numeric_limits<std::uint16_t>::max())),
            .maximumCount = static_cast<std::uint16_t>(ReadUnsigned(entry, "maximumCount", std::numeric_limits<std::uint16_t>::max())),
            .requestId = ReadUnsigned(entry, "requestId", std::numeric_limits<std::uint64_t>::max()),
        };
    }
    if (type == "acknowledge_ticket") {
        return AcknowledgeTicketCommand{
            .ticketId = ReadUnsigned(entry, "ticketId", std::numeric_limits<std::uint64_t>::max()),
        };
    }
    if (type == "reject_ticket") {
        return RejectTicketCommand{
            .ticketId = ReadUnsigned(entry, "ticketId", std::numeric_limits<std::uint64_t>::max()),
        };
    }
    if (type == "resolve_ticket") {
        return ResolveTicketCommand{
            .ticketId = ReadUnsigned(entry, "ticketId", std::numeric_limits<std::uint64_t>::max()),
            .killed = entry.at("killed").get<bool>(),
        };
    }
    throw std::runtime_error("command type is not supported");
}

}  // namespace

CommandLogLoadResult LoadCommandLogJsonl(std::span<const std::byte> jsonBytes) {
    try {
        const auto* text = reinterpret_cast<const char*>(jsonBytes.data());
        const std::string_view input(text, jsonBytes.size());
        std::vector<ScheduledCommand> commands;
        std::size_t offset = 0;
        std::uint64_t previousTick = 0;
        std::size_t lineNumber = 0;

        while (offset < input.size()) {
            const auto lineEnd = input.find('\n', offset);
            auto line = input.substr(offset, lineEnd == std::string_view::npos ? input.size() - offset : lineEnd - offset);
            offset = lineEnd == std::string_view::npos ? input.size() : lineEnd + 1;
            ++lineNumber;
            if (!line.empty() && line.back() == '\r') {
                line.remove_suffix(1);
            }
            if (line.find_first_not_of(" \t\r") == std::string_view::npos) {
                continue;
            }

            const auto entry = Json::parse(line.begin(), line.end());
            if (!entry.is_object()) {
                return {std::nullopt, "command log line " + std::to_string(lineNumber) + " must be an object"};
            }
            const auto tick = ReadUnsigned(entry, "tick", std::numeric_limits<std::uint64_t>::max());
            if (tick == 0 || tick < previousTick) {
                return {std::nullopt, "command log ticks must be positive and ordered"};
            }
            commands.push_back({.tick = tick, .command = ParseCommand(entry)});
            previousTick = tick;
        }

        return {std::move(commands), {}};
    } catch (const nlohmann::json::exception& exception) {
        return {std::nullopt, std::string("invalid command log JSON: ") + exception.what()};
    } catch (const std::exception& exception) {
        return {std::nullopt, exception.what()};
    }
}

}  // namespace zombiesim::walker