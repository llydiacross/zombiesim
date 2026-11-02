#include "keyvalues.hpp"

#include <cctype>

namespace zmv {

bool IEquals(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(a[i])) != std::tolower(static_cast<unsigned char>(b[i]))) return false;
    }
    return true;
}

std::string ToLower(std::string_view s) {
    std::string out(s);
    for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return out;
}

const std::string* KVNode::Get(std::string_view key) const {
    for (const auto& kv : keys) {
        if (IEquals(kv.first, key)) return &kv.second;
    }
    return nullptr;
}

const KVNode* KVNode::Child(std::string_view childName) const {
    for (const auto& c : children) {
        if (IEquals(c.name, childName)) return &c;
    }
    return nullptr;
}

namespace {

enum class TokType { End, String, Open, Close, Conditional };

struct Tokenizer {
    std::string_view text;
    size_t pos = 0;

    TokType Next(std::string& out) {
        for (;;) {
            while (pos < text.size() && std::isspace(static_cast<unsigned char>(text[pos]))) ++pos;
            if (pos + 1 < text.size() && text[pos] == '/' && text[pos + 1] == '/') {
                while (pos < text.size() && text[pos] != '\n') ++pos;
                continue;
            }
            break;
        }
        if (pos >= text.size()) return TokType::End;
        const char c = text[pos];
        if (c == '{') { ++pos; return TokType::Open; }
        if (c == '}') { ++pos; return TokType::Close; }
        if (c == '[') {
            const size_t end = text.find(']', pos);
            pos = end == std::string_view::npos ? text.size() : end + 1;
            return TokType::Conditional;
        }
        out.clear();
        if (c == '"') {
            ++pos;
            const size_t start = pos;
            while (pos < text.size() && text[pos] != '"') ++pos;
            out.assign(text.substr(start, pos - start));
            if (pos < text.size()) ++pos;
            return TokType::String;
        }
        const size_t start = pos;
        while (pos < text.size()) {
            const char d = text[pos];
            if (std::isspace(static_cast<unsigned char>(d)) || d == '{' || d == '}' || d == '"') break;
            ++pos;
        }
        out.assign(text.substr(start, pos - start));
        return TokType::String;
    }
};

void ParseBlock(Tokenizer& tok, KVNode& node) {
    std::string key;
    std::string value;
    for (;;) {
        TokType t = tok.Next(key);
        if (t == TokType::End || t == TokType::Close) return;
        if (t != TokType::String) continue;

        t = tok.Next(value);
        if (t == TokType::Conditional) t = tok.Next(value);
        if (t == TokType::Open) {
            KVNode child;
            child.name = key;
            ParseBlock(tok, child);
            node.children.push_back(std::move(child));
        } else if (t == TokType::String) {
            node.keys.emplace_back(key, value);
            const size_t afterValue = tok.pos;
            std::string cond;
            if (tok.Next(cond) != TokType::Conditional) tok.pos = afterValue;
        } else {
            return;
        }
    }
}

}  // namespace

KVNode ParseKeyValues(std::string_view text) {
    if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF && static_cast<unsigned char>(text[1]) == 0xBB &&
        static_cast<unsigned char>(text[2]) == 0xBF) {
        text.remove_prefix(3);
    }
    KVNode root;
    Tokenizer tok{text, 0};
    ParseBlock(tok, root);
    return root;
}

}  // namespace zmv
