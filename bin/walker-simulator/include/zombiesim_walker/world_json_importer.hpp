#pragma once

#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <string_view>

#include "zombiesim_walker/world_graph.hpp"

namespace zombiesim::walker {

struct WorldLoadResult {
    std::optional<WorldGraph> graph;
    std::string error;

    [[nodiscard]] explicit operator bool() const noexcept { return graph.has_value(); }
};

[[nodiscard]] WorldLoadResult LoadWorldJson(
    std::span<const std::byte> jsonBytes,
    std::string_view expectedProfileId);

}  // namespace zombiesim::walker