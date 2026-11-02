#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace zmv {

// Generic Valve KeyValues tree, used for both VMF and VMT text.
struct KVNode {
    std::string name;
    std::vector<std::pair<std::string, std::string>> keys;
    std::vector<KVNode> children;

    // Case-insensitive lookup of the first matching key; nullptr when absent.
    const std::string* Get(std::string_view key) const;
    const KVNode* Child(std::string_view name) const;
};

// Parses KeyValues text into a root node whose children are the top-level blocks.
// Malformed input never throws; parsing stops at the first unrecoverable token.
KVNode ParseKeyValues(std::string_view text);

bool IEquals(std::string_view a, std::string_view b);
std::string ToLower(std::string_view s);

}  // namespace zmv
