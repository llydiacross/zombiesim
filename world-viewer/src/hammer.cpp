#include "hammer.hpp"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

namespace zmv {

bool OpenInHammer(const std::filesystem::path& hammerExe, const std::filesystem::path& vmf, std::string& error) {
    std::error_code ec;
    if (hammerExe.empty() || !std::filesystem::exists(hammerExe, ec)) {
        error = "Hammer not found: " + hammerExe.string();
        return false;
    }
    if (!std::filesystem::exists(vmf, ec)) {
        error = "VMF not found: " + vmf.string();
        return false;
    }
#ifdef _WIN32
    const std::filesystem::path absoluteVmf = std::filesystem::absolute(vmf, ec);
    std::wstring command = L"\"" + hammerExe.wstring() + L"\" \"" + absoluteVmf.wstring() + L"\"";
    const std::wstring workingDirectory = hammerExe.parent_path().wstring();
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(hammerExe.wstring().c_str(), command.data(), nullptr, nullptr, FALSE,
                        DETACHED_PROCESS, nullptr, workingDirectory.c_str(), &startup, &process)) {
        error = "CreateProcess failed (" + std::to_string(GetLastError()) + ")";
        return false;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
#else
    error = "Opening Hammer is only supported on Windows";
    return false;
#endif
}

}  // namespace zmv
