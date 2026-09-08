#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "zombiesim_walker/command_types.hpp"

namespace zombiesim::walker {

struct ScheduledCommand {
    std::uint64_t tick = 0;
    WalkerCommand command;
};

struct CommandLogLoadResult {
    std::optional<std::vector<ScheduledCommand>> commands;
    std::string error;

    [[nodiscard]] explicit operator bool() const noexcept { return commands.has_value(); }
};

[[nodiscard]] CommandLogLoadResult LoadCommandLogJsonl(std::span<const std::byte> jsonBytes);

}  // namespace zombiesim::walker