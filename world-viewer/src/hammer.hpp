#pragma once

#include <filesystem>
#include <string>

namespace zmv {

// Starts Hammer (or Hammer++) detached with the given VMF. Returns false and fills error on failure.
bool OpenInHammer(const std::filesystem::path& hammerExe, const std::filesystem::path& vmf, std::string& error);

}  // namespace zmv
