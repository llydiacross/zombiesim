#pragma once

#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace zmv {

// Read-only index of a Valve VPK (v1/v2) directory file and its numbered archives.
class VpkArchive {
public:
    bool Open(const std::filesystem::path& dirFile);
    // Reads up to maxBytes (0 = whole file) of a lower-case, forward-slash path.
    bool Read(const std::string& path, std::string& out, size_t maxBytes = 0) const;
    size_t Count() const { return entries_.size(); }

private:
    struct Entry {
        uint16_t archiveIndex = 0;
        uint32_t offset = 0;
        uint32_t length = 0;
        uint32_t preloadOffset = 0;
        uint16_t preloadBytes = 0;
    };
    std::filesystem::path dirFile_;
    std::string basePrefix_;
    uint64_t dataStart_ = 0;
    std::string preload_;
    std::unordered_map<std::string, Entry> entries_;
};

// Search path over loose folders and VPKs, mirroring the mounted game content order.
class GameFileSystem {
public:
    void AddLooseRoot(const std::filesystem::path& root);
    void AddVpk(const std::filesystem::path& dirFile);
    bool Read(const std::string& relativePath, std::string& out, size_t maxBytes = 0) const;
    std::vector<std::string> Describe() const;

private:
    std::vector<std::filesystem::path> loose_;
    std::vector<std::unique_ptr<VpkArchive>> vpks_;
    std::vector<std::string> description_;
};

bool ReadFileBytes(const std::filesystem::path& path, std::string& out, size_t maxBytes = 0);

}  // namespace zmv
