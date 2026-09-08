#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <type_traits>

namespace zombiesim::walker {

class DeterministicHasher {
public:
    void AppendByte(std::uint8_t value) {
        value_ ^= value;
        value_ *= kFnvPrime;
    }

    template <typename Integer>
        requires(std::is_integral_v<Integer> && !std::is_same_v<std::remove_cv_t<Integer>, bool>)
    void AppendInteger(Integer value) {
        using Unsigned = std::make_unsigned_t<Integer>;
        const auto unsignedValue = static_cast<Unsigned>(value);
        for (std::size_t byteIndex = 0; byteIndex < sizeof(Unsigned); ++byteIndex) {
            AppendByte(static_cast<std::uint8_t>(unsignedValue >> (byteIndex * 8U)));
        }
    }

    void AppendBoolean(bool value) { AppendByte(value ? 1U : 0U); }

    void AppendString(std::string_view value) {
        AppendInteger(static_cast<std::uint32_t>(value.size()));
        for (const auto character : value) {
            AppendByte(static_cast<std::uint8_t>(static_cast<unsigned char>(character)));
        }
    }

    [[nodiscard]] std::uint64_t Value() const noexcept { return value_; }

private:
    static constexpr std::uint64_t kFnvOffset = 14695981039346656037ULL;
    static constexpr std::uint64_t kFnvPrime = 1099511628211ULL;
    std::uint64_t value_ = kFnvOffset;
};

}  // namespace zombiesim::walker