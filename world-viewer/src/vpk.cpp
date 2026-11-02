#include "vpk.hpp"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>

#include "keyvalues.hpp"

namespace zmv {

bool ReadFileBytes(const std::filesystem::path& path, std::string& out, size_t maxBytes) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    in.seekg(0, std::ios::end);
    const auto size = static_cast<size_t>(in.tellg());
    const size_t want = (maxBytes != 0 && maxBytes < size) ? maxBytes : size;
    in.seekg(0, std::ios::beg);
    out.resize(want);
    if (want > 0) in.read(out.data(), static_cast<std::streamsize>(want));
    return static_cast<bool>(in) || in.eof();
}

namespace {

template <typename T>
bool ReadPod(const std::string& data, size_t& pos, T& value) {
    if (pos + sizeof(T) > data.size()) return false;
    std::memcpy(&value, data.data() + pos, sizeof(T));
    pos += sizeof(T);
    return true;
}

bool ReadCString(const std::string& data, size_t& pos, std::string& out) {
    const size_t end = data.find('\0', pos);
    if (end == std::string::npos) return false;
    out.assign(data, pos, end - pos);
    pos = end + 1;
    return true;
}

}  // namespace

bool VpkArchive::Open(const std::filesystem::path& dirFile) {
    std::string data;
    if (!ReadFileBytes(dirFile, data)) return false;
    size_t pos = 0;
    uint32_t signature = 0, version = 0, treeSize = 0;
    if (!ReadPod(data, pos, signature) || signature != 0x55aa1234u) return false;
    if (!ReadPod(data, pos, version) || !ReadPod(data, pos, treeSize)) return false;
    size_t headerSize = 12;
    if (version == 2) headerSize = 28;
    else if (version != 1) return false;
    pos = headerSize;
    dataStart_ = headerSize + treeSize;

    dirFile_ = dirFile;
    std::string stem = dirFile.filename().string();
    const std::string suffix = "_dir.vpk";
    if (stem.size() > suffix.size()) stem = stem.substr(0, stem.size() - suffix.size());
    basePrefix_ = (dirFile.parent_path() / stem).string();

    std::string ext, dir, name;
    while (pos < data.size()) {
        if (!ReadCString(data, pos, ext)) return false;
        if (ext.empty()) break;
        for (;;) {
            if (!ReadCString(data, pos, dir)) return false;
            if (dir.empty()) break;
            for (;;) {
                if (!ReadCString(data, pos, name)) return false;
                if (name.empty()) break;
                uint32_t crc = 0;
                uint16_t preloadBytes = 0, archiveIndex = 0, terminator = 0;
                uint32_t offset = 0, length = 0;
                if (!ReadPod(data, pos, crc) || !ReadPod(data, pos, preloadBytes) || !ReadPod(data, pos, archiveIndex) ||
                    !ReadPod(data, pos, offset) || !ReadPod(data, pos, length) || !ReadPod(data, pos, terminator)) {
                    return false;
                }
                Entry e;
                e.archiveIndex = archiveIndex;
                e.offset = offset;
                e.length = length;
                e.preloadBytes = preloadBytes;
                e.preloadOffset = static_cast<uint32_t>(preload_.size());
                if (preloadBytes > 0) {
                    if (pos + preloadBytes > data.size()) return false;
                    preload_.append(data, pos, preloadBytes);
                    pos += preloadBytes;
                }
                std::string full = (dir == " " ? std::string() : dir + "/") + name + (ext == " " ? std::string() : "." + ext);
                entries_.emplace(ToLower(full), e);
            }
        }
    }
    return true;
}

bool VpkArchive::Read(const std::string& path, std::string& out, size_t maxBytes) const {
    const auto it = entries_.find(path);
    if (it == entries_.end()) return false;
    const Entry& e = it->second;
    const size_t total = static_cast<size_t>(e.preloadBytes) + e.length;
    const size_t want = (maxBytes != 0 && maxBytes < total) ? maxBytes : total;
    out.assign(preload_, e.preloadOffset, std::min<size_t>(e.preloadBytes, want));
    if (out.size() >= want || e.length == 0) return true;

    std::filesystem::path archive;
    uint64_t offset = e.offset;
    if (e.archiveIndex == 0x7fff) {
        archive = dirFile_;
        offset += dataStart_;
    } else {
        char buffer[16];
        std::snprintf(buffer, sizeof(buffer), "_%03u.vpk", static_cast<unsigned>(e.archiveIndex));
        archive = basePrefix_ + buffer;
    }
    std::ifstream in(archive, std::ios::binary);
    if (!in) return false;
    in.seekg(static_cast<std::streamoff>(offset));
    const size_t remaining = want - out.size();
    const size_t start = out.size();
    out.resize(want);
    in.read(out.data() + start, static_cast<std::streamsize>(remaining));
    return static_cast<bool>(in);
}

void GameFileSystem::AddLooseRoot(const std::filesystem::path& root) {
    if (!std::filesystem::is_directory(root)) return;
    loose_.push_back(root);
    description_.push_back("loose " + root.string());
}

void GameFileSystem::AddVpk(const std::filesystem::path& dirFile) {
    auto vpk = std::make_unique<VpkArchive>();
    if (!vpk->Open(dirFile)) return;
    description_.push_back("vpk " + dirFile.filename().string() + " (" + std::to_string(vpk->Count()) + " files)");
    vpks_.push_back(std::move(vpk));
}

bool GameFileSystem::Read(const std::string& relativePath, std::string& out, size_t maxBytes) const {
    const std::string key = ToLower(relativePath);
    for (const auto& root : loose_) {
        const auto candidate = root / key;
        std::error_code ec;
        if (std::filesystem::is_regular_file(candidate, ec) && ReadFileBytes(candidate, out, maxBytes)) return true;
    }
    for (const auto& vpk : vpks_) {
        if (vpk->Read(key, out, maxBytes)) return true;
    }
    return false;
}

std::vector<std::string> GameFileSystem::Describe() const { return description_; }

}  // namespace zmv
