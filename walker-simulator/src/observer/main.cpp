#include "zombiesim_walker/command_log.hpp"
#include "zombiesim_walker/walker_config.hpp"
#include "zombiesim_walker/walker_simulator.hpp"
#include "zombiesim_walker/world_json_importer.hpp"

#include <charconv>
#include <cstddef>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace {

std::vector<std::byte> ReadBytes(const std::string& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return {};
    }
    const std::vector<char> characters(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());
    std::vector<std::byte> bytes;
    bytes.reserve(characters.size());
    for (const auto character : characters) {
        bytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(character)));
    }
    return bytes;
}

bool ParseUnsigned(std::string_view input, std::uint64_t& value) {
    const auto result = std::from_chars(input.data(), input.data() + input.size(), value);
    return result.ec == std::errc{} && result.ptr == input.data() + input.size();
}

void PrintUsage() {
    std::cerr << "Usage: zombiesim-walker-observer --world <runtime-json> --profile <id> "
                 "--config <walker-config-json> [--ticks <count>] "
                 "[--command-log <jsonl>] [--noise <cell> <strength> <radius> <duration-ticks>]\n";
}

}  // namespace

int main(int argumentCount, char** arguments) {
    std::string worldPath;
    std::string profileId;
    std::string configPath;
    std::string commandLogPath;
    std::uint64_t ticks = 0;
    bool ticksSpecified = false;
    std::vector<zombiesim::walker::NoiseCommand> noiseCommands;

    for (int index = 1; index < argumentCount; ++index) {
        const std::string_view argument = arguments[index];
        const auto nextValue = [&]() -> std::string_view {
            if (++index >= argumentCount) {
                PrintUsage();
                std::exit(2);
            }
            return arguments[index];
        };

        if (argument == "--world") {
            worldPath = nextValue();
        } else if (argument == "--profile") {
            profileId = nextValue();
        } else if (argument == "--config") {
            configPath = nextValue();
        } else if (argument == "--ticks") {
            if (!ParseUnsigned(nextValue(), ticks)) {
                PrintUsage();
                return 2;
            }
            ticksSpecified = true;
        } else if (argument == "--command-log") {
            commandLogPath = nextValue();
        } else if (argument == "--noise") {
            std::uint64_t cellId = 0;
            std::uint64_t strength = 0;
            std::uint64_t radius = 0;
            std::uint64_t duration = 0;
            if (!ParseUnsigned(nextValue(), cellId) || !ParseUnsigned(nextValue(), strength) ||
                !ParseUnsigned(nextValue(), radius) || !ParseUnsigned(nextValue(), duration) ||
                cellId > std::numeric_limits<std::uint16_t>::max() ||
                strength > std::numeric_limits<std::uint16_t>::max() ||
                radius > std::numeric_limits<std::uint16_t>::max() ||
                duration > std::numeric_limits<std::uint16_t>::max()) {
                PrintUsage();
                return 2;
            }
            noiseCommands.push_back({
                .cellId = static_cast<std::uint16_t>(cellId),
                .strength = static_cast<std::uint16_t>(strength),
                .radiusInCells = static_cast<std::uint16_t>(radius),
                .durationTicks = static_cast<std::uint16_t>(duration),
            });
        } else {
            PrintUsage();
            return 2;
        }
    }

    if (worldPath.empty() || profileId.empty() || configPath.empty()) {
        PrintUsage();
        return 2;
    }

    const auto config = zombiesim::walker::LoadWalkerConfigJson(ReadBytes(configPath));
    if (!config) {
        std::cerr << "Config error: " << config.error << '\n';
        return 1;
    }
    const auto world = zombiesim::walker::LoadWorldJson(ReadBytes(worldPath), profileId);
    if (!world) {
        std::cerr << "World error: " << world.error << '\n';
        return 1;
    }

    zombiesim::walker::WalkerSimulator simulator;
    std::string error;
    if (!simulator.Initialize(*world.graph, *config.config, &error)) {
        std::cerr << "Simulation error: " << error << '\n';
        return 1;
    }
    std::vector<zombiesim::walker::ScheduledCommand> scheduledCommands;
    if (!commandLogPath.empty()) {
        const auto commandLog = zombiesim::walker::LoadCommandLogJsonl(ReadBytes(commandLogPath));
        if (!commandLog) {
            std::cerr << "Command log error: " << commandLog.error << '\n';
            return 1;
        }
        scheduledCommands = *commandLog.commands;
        if (!ticksSpecified && !scheduledCommands.empty()) {
            ticks = scheduledCommands.back().tick;
        }
    }
    for (const auto& noise : noiseCommands) {
        if (!simulator.Submit({noise}, &error)) {
            std::cerr << "Command error: " << error << '\n';
            return 1;
        }
    }
    std::size_t commandIndex = 0;
    for (std::uint64_t tick = 1; tick <= ticks; ++tick) {
        while (commandIndex < scheduledCommands.size() && scheduledCommands[commandIndex].tick == tick) {
            if (!simulator.Submit(scheduledCommands[commandIndex].command, &error)) {
                std::cerr << "Command error: " << error << '\n';
                return 1;
            }
            ++commandIndex;
        }
        static_cast<void>(simulator.AdvanceOneTick());
    }

    const auto& snapshot = simulator.Snapshot();
    std::cout << "graph_revision_hash=" << snapshot.graphRevisionHash << '\n';
    std::cout << "tick=" << snapshot.tick << '\n';
    std::cout << "state_hash=" << snapshot.stateHash << '\n';
    std::cout << "population=" << snapshot.totalPopulation << '\n';
    std::cout << "hordes=" << snapshot.hordes.size() << '\n';
    std::cout << "tickets=" << snapshot.tickets.size() << '\n';
    return 0;
}