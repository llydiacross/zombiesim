#include "zombiesim_walker/walker_config.hpp"

#include <exception>
#include <limits>
#include <string>

#include <nlohmann/json.hpp>

#include "zombiesim_walker/deterministic_hash.hpp"

namespace zombiesim::walker {
namespace {

using Json = nlohmann::json;

[[nodiscard]] std::uint64_t ReadBoundedUnsigned(
    const Json& root,
    const char* fieldName,
    std::uint64_t minimum,
    std::uint64_t maximum) {
    const auto& value = root.at(fieldName);
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
    if (number < minimum || number > maximum) {
        throw std::runtime_error(std::string(fieldName) + " is out of range");
    }
    return number;
}

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

}  // namespace

bool ValidateWalkerConfig(const WalkerConfig& config, std::string* error) {
    if (config.version != 1) {
        SetError(error, "unsupported walker config version");
        return false;
    }
    if (config.minimumGroupSize == 0 || config.minimumGroupSize > config.maximumGroupSize) {
        SetError(error, "group size bounds are invalid");
        return false;
    }
    if (config.progressPerTick == 0 || config.progressPerTick > 1000) {
        SetError(error, "progressPerTick must be between 1 and 1000");
        return false;
    }
    if (config.attractionDecayPermille > 1000) {
        SetError(error, "attractionDecayPermille must be between 0 and 1000");
        return false;
    }
    if (config.safeZonePenalty < 0) {
        SetError(error, "safeZonePenalty must not be negative");
        return false;
    }
    if (config.ticketLifetimeTicks == 0 || config.maximumTicketsPerRequest == 0) {
        SetError(error, "ticket limits must be positive");
        return false;
    }
    return true;
}

ConfigLoadResult LoadWalkerConfigJson(std::span<const std::byte> jsonBytes) {
    try {
        if (jsonBytes.empty()) {
            return {std::nullopt, "walker config JSON is empty"};
        }

        const auto* text = reinterpret_cast<const char*>(jsonBytes.data());
        const Json root = Json::parse(text, text + jsonBytes.size());
        if (!root.is_object()) {
            return {std::nullopt, "walker config root must be an object"};
        }

        WalkerConfig config;
        config.version = static_cast<std::uint16_t>(ReadBoundedUnsigned(root, "version", 1, 1));
        config.minimumGroupSize = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "minimumGroupSize",
            1,
            std::numeric_limits<std::uint16_t>::max()));
        config.maximumGroupSize = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "maximumGroupSize",
            1,
            std::numeric_limits<std::uint16_t>::max()));
        config.progressPerTick = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "progressPerTick",
            1,
            1000));
        config.attractionDecayPermille = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "attractionDecayPermille",
            0,
            1000));
        config.safeZonePenalty = static_cast<std::int32_t>(ReadBoundedUnsigned(
            root,
            "safeZonePenalty",
            0,
            std::numeric_limits<std::int32_t>::max()));
        config.ticketLifetimeTicks = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "ticketLifetimeTicks",
            1,
            std::numeric_limits<std::uint16_t>::max()));
        config.maximumTicketsPerRequest = static_cast<std::uint16_t>(ReadBoundedUnsigned(
            root,
            "maximumTicketsPerRequest",
            1,
            std::numeric_limits<std::uint16_t>::max()));

        std::string error;
        if (!ValidateWalkerConfig(config, &error)) {
            return {std::nullopt, std::move(error)};
        }
        return {config, {}};
    } catch (const nlohmann::json::exception& exception) {
        return {std::nullopt, std::string("invalid walker config JSON: ") + exception.what()};
    } catch (const std::exception& exception) {
        return {std::nullopt, exception.what()};
    }
}

std::uint64_t ComputeWalkerConfigHash(const WalkerConfig& config) {
    DeterministicHasher hash;
    hash.AppendInteger(config.version);
    hash.AppendInteger(config.minimumGroupSize);
    hash.AppendInteger(config.maximumGroupSize);
    hash.AppendInteger(config.progressPerTick);
    hash.AppendInteger(config.attractionDecayPermille);
    hash.AppendInteger(config.safeZonePenalty);
    hash.AppendInteger(config.ticketLifetimeTicks);
    hash.AppendInteger(config.maximumTicketsPerRequest);
    return hash.Value();
}

}  // namespace zombiesim::walker