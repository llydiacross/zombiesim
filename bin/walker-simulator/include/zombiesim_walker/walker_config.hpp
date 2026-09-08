#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>

namespace zombiesim::walker {

struct WalkerConfig {
    std::uint16_t version = 1;
    std::uint16_t minimumGroupSize = 4;
    std::uint16_t maximumGroupSize = 64;
    std::uint16_t progressPerTick = 250;
    std::uint16_t attractionDecayPermille = 920;
    std::int32_t safeZonePenalty = 100000;
    std::uint16_t ticketLifetimeTicks = 20;
    std::uint16_t maximumTicketsPerRequest = 12;
};

struct ConfigLoadResult {
    std::optional<WalkerConfig> config;
    std::string error;

    [[nodiscard]] explicit operator bool() const noexcept { return config.has_value(); }
};

[[nodiscard]] bool ValidateWalkerConfig(const WalkerConfig& config, std::string* error = nullptr);
[[nodiscard]] ConfigLoadResult LoadWalkerConfigJson(std::span<const std::byte> jsonBytes);
[[nodiscard]] std::uint64_t ComputeWalkerConfigHash(const WalkerConfig& config);

}  // namespace zombiesim::walker