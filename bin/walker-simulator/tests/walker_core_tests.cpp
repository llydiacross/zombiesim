#include "zombiesim_walker/command_log.hpp"
#include "zombiesim_walker/walker_simulator.hpp"
#include "zombiesim_walker/world_json_importer.hpp"

#include <algorithm>
#include <cstddef>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

namespace {

int failures = 0;

struct ExpectedState {
    std::uint64_t tick = 0;
    std::uint64_t stateHash = 0;
    std::uint64_t totalPopulation = 0;
    std::size_t hordeCount = 0;
    std::size_t ticketCount = 0;
};

struct ExpectedStateFixture {
    std::uint64_t graphRevisionHash = 0;
    std::vector<ExpectedState> states;
};

void Expect(bool condition, const std::string& message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

std::vector<std::byte> ReadBytes(const char* path) {
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

std::vector<std::byte> Bytes(std::string_view text) {
    std::vector<std::byte> bytes;
    bytes.reserve(text.size());
    for (const auto character : text) {
        bytes.push_back(static_cast<std::byte>(static_cast<unsigned char>(character)));
    }
    return bytes;
}

std::optional<ExpectedStateFixture> LoadExpectedStates(const char* path) {
    const auto bytes = ReadBytes(path);
    if (bytes.empty()) {
        return std::nullopt;
    }

    try {
        const auto* text = reinterpret_cast<const char*>(bytes.data());
        const auto root = nlohmann::json::parse(text, text + bytes.size());
        ExpectedStateFixture fixture;
        fixture.graphRevisionHash = root.at("graphRevisionHash").get<std::uint64_t>();
        for (const auto& state : root.at("states")) {
            fixture.states.push_back({
                .tick = state.at("tick").get<std::uint64_t>(),
                .stateHash = state.at("stateHash").get<std::uint64_t>(),
                .totalPopulation = state.at("totalPopulation").get<std::uint64_t>(),
                .hordeCount = state.at("hordeCount").get<std::size_t>(),
                .ticketCount = state.at("ticketCount").get<std::size_t>(),
            });
        }
        return fixture;
    } catch (const nlohmann::json::exception&) {
        return std::nullopt;
    }
}

zombiesim::walker::WalkerSimulator MakeSimulator(
    const zombiesim::walker::WorldGraph& graph,
    const zombiesim::walker::WalkerConfig& config) {
    zombiesim::walker::WalkerSimulator simulator;
    std::string error;
    Expect(simulator.Initialize(graph, config, &error), "simulator initializes: " + error);
    return simulator;
}

const zombiesim::walker::TicketSummary* FindTicket(
    const zombiesim::walker::OutputSnapshot& snapshot,
    zombiesim::walker::TicketState state) {
    const auto iterator = std::find_if(
        snapshot.tickets.begin(),
        snapshot.tickets.end(),
        [state](const zombiesim::walker::TicketSummary& ticket) { return ticket.state == state; });
    return iterator == snapshot.tickets.end() ? nullptr : &*iterator;
}

}  // namespace

int main() {
    const auto configBytes = ReadBytes(ZMWALKER_CONFIG_JSON);
    Expect(!configBytes.empty(), "walker config fixture is readable");
    const auto config = zombiesim::walker::LoadWalkerConfigJson(configBytes);
    Expect(static_cast<bool>(config), "walker config fixture imports");

    const auto previewBytes = ReadBytes(ZMWALKER_PREVIEW_WORLD_JSON);
    Expect(!previewBytes.empty(), "preview world fixture is readable");
    const auto preview = zombiesim::walker::LoadWorldJson(previewBytes, "preview");
    Expect(static_cast<bool>(preview), "preview world imports successfully");
    if (!config || !preview) {
        return 1;
    }

    Expect(preview.graph->cells.size() == 576, "preview world has 576 logical cells");
    Expect(preview.graph->population == 81000, "preview world carries the 81,000 generator population");
    Expect(preview.graph->revisionHash != 0, "preview graph receives a revision hash");
    Expect(!preview.graph->IsSafeZone(0), "cell zero is not a safe zone");
    const auto wrongProfile = zombiesim::walker::LoadWorldJson(previewBytes, "city");
    Expect(!wrongProfile, "profile mismatch is rejected");

    constexpr std::string_view duplicateId = R"json({
        "schemaVersion": 1,
        "world": {
            "mapDirectory": "preview",
            "mapManifestSha256": "fixture",
            "templatePlanSha256": "fixture",
            "seed": 1,
            "population": 8,
            "grid": [2, 1],
            "gridOrigin": [0, 0]
        },
        "cells": [
            {"id": 0, "danger": 0, "radiation": 0, "safeZone": null, "exits": []},
            {"id": 0, "danger": 0, "radiation": 0, "safeZone": null, "exits": []}
        ]
    })json";
    const auto invalid = zombiesim::walker::LoadWorldJson(Bytes(duplicateId), "preview");
    Expect(!invalid, "duplicate cell ids are rejected");

    auto first = MakeSimulator(*preview.graph, *config.config);
    auto second = MakeSimulator(*preview.graph, *config.config);
    const auto commandLog = zombiesim::walker::LoadCommandLogJsonl(ReadBytes(ZMWALKER_COMMAND_LOG_JSONL));
    Expect(static_cast<bool>(commandLog), "command log fixture imports");
    const auto expectedStates = LoadExpectedStates(ZMWALKER_EXPECTED_HASHES_JSON);
    Expect(expectedStates.has_value(), "expected state hash fixture imports");
    if (!commandLog || !expectedStates) {
        return 1;
    }
    std::string error;
    Expect(
        first.Snapshot().graphRevisionHash == expectedStates->graphRevisionHash,
        "preview graph revision matches the parity fixture");
    Expect(
        first.Snapshot().stateHash == expectedStates->states.front().stateHash,
        "initial state matches the parity fixture");
    Expect(
        first.Snapshot().totalPopulation == preview.graph->population,
        "initial walker population exactly matches the exported world population");
    std::size_t commandIndex = 0;
    std::size_t expectedStateIndex = 1;
    for (int tick = 0; tick < 16; ++tick) {
        while (commandIndex < commandLog.commands->size() &&
               (*commandLog.commands)[commandIndex].tick == static_cast<std::uint64_t>(tick + 1)) {
            const auto& command = (*commandLog.commands)[commandIndex].command;
            Expect(first.Submit(command, &error), "first accepts command log entry: " + error);
            Expect(second.Submit(command, &error), "second accepts command log entry: " + error);
            ++commandIndex;
        }
        const auto firstSnapshot = first.AdvanceOneTick();
        const auto secondSnapshot = second.AdvanceOneTick();
        Expect(firstSnapshot.stateHash == secondSnapshot.stateHash, "same command stream has the same state hash");
        if (expectedStateIndex < expectedStates->states.size() &&
            firstSnapshot.tick == expectedStates->states[expectedStateIndex].tick) {
            const auto& expected = expectedStates->states[expectedStateIndex++];
            Expect(firstSnapshot.stateHash == expected.stateHash, "replay state hash matches parity fixture");
            Expect(firstSnapshot.totalPopulation == expected.totalPopulation, "replay population matches parity fixture");
            Expect(firstSnapshot.hordes.size() == expected.hordeCount, "replay horde count matches parity fixture");
            Expect(firstSnapshot.tickets.size() == expected.ticketCount, "replay ticket count matches parity fixture");
        }
    }
    Expect(expectedStateIndex == expectedStates->states.size(), "all expected parity states were replayed");

    auto ledger = MakeSimulator(*preview.graph, *config.config);
    const auto initialPopulation = ledger.Snapshot().totalPopulation;
    Expect(initialPopulation > 0, "initial virtual population is non-zero");
    Expect(ledger.Submit({zombiesim::walker::RequestSpawnTicketsCommand{.cellId = 0, .maximumCount = 2, .requestId = 1}}, &error), "ticket request is accepted: " + error);
    const auto reserved = ledger.AdvanceOneTick();
    Expect(reserved.totalPopulation == initialPopulation, "reservation preserves total population");
    const auto* ticket = FindTicket(reserved, zombiesim::walker::TicketState::Reserved);
    Expect(ticket != nullptr, "ticket request creates a reservation");
    if (ticket != nullptr) {
        Expect(ledger.Submit({zombiesim::walker::AcknowledgeTicketCommand{.ticketId = ticket->ticketId}}, &error), "ticket acknowledgement is accepted: " + error);
        const auto materialized = ledger.AdvanceOneTick();
        Expect(materialized.totalPopulation == initialPopulation, "materialization preserves total population");

        Expect(ledger.Submit({zombiesim::walker::ResolveTicketCommand{.ticketId = ticket->ticketId, .killed = false}}, &error), "ticket despawn is accepted: " + error);
        const auto despawned = ledger.AdvanceOneTick();
        Expect(despawned.totalPopulation == initialPopulation, "a despawned ticket returns population once");

        Expect(ledger.Submit({zombiesim::walker::RequestSpawnTicketsCommand{.cellId = 0, .maximumCount = 2, .requestId = 2}}, &error), "second ticket request is accepted: " + error);
        const auto secondReserved = ledger.AdvanceOneTick();
        Expect(
            secondReserved.totalPopulation == initialPopulation,
            "second reservation preserves population: expected " + std::to_string(initialPopulation) +
                ", got " + std::to_string(secondReserved.totalPopulation));
        const auto* secondTicket = FindTicket(secondReserved, zombiesim::walker::TicketState::Reserved);
        Expect(secondTicket != nullptr, "second ticket request creates a reservation");
        if (secondTicket != nullptr) {
            Expect(ledger.Submit({zombiesim::walker::RejectTicketCommand{.ticketId = secondTicket->ticketId}}, &error), "ticket rejection is accepted: " + error);
            const auto rejected = ledger.AdvanceOneTick();
            Expect(
                rejected.totalPopulation == initialPopulation,
                "a rejected ticket preserves population: expected " + std::to_string(initialPopulation) +
                    ", got " + std::to_string(rejected.totalPopulation));
            const auto* killTicket = FindTicket(rejected, zombiesim::walker::TicketState::Reserved);
            Expect(killTicket != nullptr, "a reservation remains available for acknowledgement");
            if (killTicket != nullptr) {
                Expect(ledger.Submit({zombiesim::walker::AcknowledgeTicketCommand{.ticketId = killTicket->ticketId}}, &error), "second ticket acknowledgement is accepted: " + error);
                static_cast<void>(ledger.AdvanceOneTick());
                Expect(ledger.Submit({zombiesim::walker::ResolveTicketCommand{.ticketId = killTicket->ticketId, .killed = true}}, &error), "ticket death is accepted: " + error);
            }
        }
        const auto killed = ledger.AdvanceOneTick();
        Expect(
            killed.totalPopulation + 1 == initialPopulation,
            "a killed ticket removes population once: expected " + std::to_string(initialPopulation - 1) +
                ", got " + std::to_string(killed.totalPopulation));
    }

    auto expiry = MakeSimulator(*preview.graph, *config.config);
    const auto expiryInitialPopulation = expiry.Snapshot().totalPopulation;
    Expect(expiry.Submit({zombiesim::walker::RequestSpawnTicketsCommand{.cellId = 0, .maximumCount = 1, .requestId = 1}}, &error), "expiry ticket request is accepted: " + error);
    static_cast<void>(expiry.AdvanceOneTick());
    for (std::uint16_t tick = 0; tick <= config.config->ticketLifetimeTicks; ++tick) {
        static_cast<void>(expiry.AdvanceOneTick());
    }
    Expect(
        expiry.Snapshot().totalPopulation == expiryInitialPopulation,
        "an expired ticket preserves population: expected " + std::to_string(expiryInitialPopulation) +
            ", got " + std::to_string(expiry.Snapshot().totalPopulation));
    Expect(FindTicket(expiry.Snapshot(), zombiesim::walker::TicketState::Expired) != nullptr, "an unanswered ticket expires");

    auto idempotence = MakeSimulator(*preview.graph, *config.config);
    Expect(
        idempotence.Submit({zombiesim::walker::RequestSpawnTicketsCommand{
            .cellId = 0,
            .maximumCount = 1,
            .requestId = 0x100000001ULL}}, &error),
        "high-half request id is accepted: " + error);
    static_cast<void>(idempotence.AdvanceOneTick());
    Expect(
        idempotence.Submit({zombiesim::walker::RequestSpawnTicketsCommand{
            .cellId = 0,
            .maximumCount = 1,
            .requestId = 1}}, &error),
        "low-half request id is accepted independently: " + error);
    const auto exactIdSnapshot = idempotence.AdvanceOneTick();
    Expect(exactIdSnapshot.tickets.size() == 2, "request ids retain their exact 64-bit values");
    Expect(
        idempotence.Submit({zombiesim::walker::RequestSpawnTicketsCommand{
            .cellId = 0,
            .maximumCount = 1,
            .requestId = 0x100000001ULL}}, &error),
        "duplicate request submission is accepted idempotently: " + error);
    const auto replayedRequest = idempotence.AdvanceOneTick();
    Expect(replayedRequest.tickets.size() == 2, "replayed request id does not reserve another ticket");
    const auto* idempotentTicket = FindTicket(replayedRequest, zombiesim::walker::TicketState::Reserved);
    Expect(idempotentTicket != nullptr, "idempotence fixture retains a reserved ticket");
    if (idempotentTicket != nullptr) {
        Expect(idempotence.Submit({zombiesim::walker::AcknowledgeTicketCommand{.ticketId = idempotentTicket->ticketId}}, &error), "first acknowledgement is accepted: " + error);
        static_cast<void>(idempotence.AdvanceOneTick());
        Expect(idempotence.Submit({zombiesim::walker::AcknowledgeTicketCommand{.ticketId = idempotentTicket->ticketId}}, &error), "duplicate acknowledgement is accepted harmlessly: " + error);
        static_cast<void>(idempotence.AdvanceOneTick());
        Expect(idempotence.Submit({zombiesim::walker::ResolveTicketCommand{.ticketId = idempotentTicket->ticketId, .killed = false}}, &error), "first resolution is accepted: " + error);
        const auto resolvedOnce = idempotence.AdvanceOneTick();
        Expect(idempotence.Submit({zombiesim::walker::ResolveTicketCommand{.ticketId = idempotentTicket->ticketId, .killed = false}}, &error), "duplicate resolution is accepted harmlessly: " + error);
        const auto resolvedTwice = idempotence.AdvanceOneTick();
        Expect(resolvedOnce.totalPopulation == resolvedTwice.totalPopulation, "duplicate resolution does not change population twice");
    }

    auto capacity = MakeSimulator(*preview.graph, *config.config);
    Expect(
        !capacity.Submit({zombiesim::walker::RequestSpawnTicketsCommand{
            .cellId = 0,
            .maximumCount = static_cast<std::uint16_t>(config.config->maximumTicketsPerRequest + 1),
            .requestId = 1}}, &error),
        "ticket request above configured capacity is rejected");

    auto retentionConfig = *config.config;
    retentionConfig.progressPerTick = 1;
    retentionConfig.ticketLifetimeTicks = 1000;
    auto retention = MakeSimulator(*preview.graph, retentionConfig);
    for (std::uint64_t requestId = 1; requestId <= 22; ++requestId) {
        Expect(
            retention.Submit({zombiesim::walker::RequestSpawnTicketsCommand{
                .cellId = 0,
                .maximumCount = 12,
                .requestId = requestId}}, &error),
            "retention ticket request is accepted: " + error);
        const auto reservedTickets = retention.AdvanceOneTick();
        for (const auto& reservedTicket : reservedTickets.tickets) {
            if (reservedTicket.state == zombiesim::walker::TicketState::Reserved) {
                Expect(retention.Submit({zombiesim::walker::RejectTicketCommand{.ticketId = reservedTicket.ticketId}}, &error), "retention ticket rejection is accepted: " + error);
            }
        }
        static_cast<void>(retention.AdvanceOneTick());
    }
    Expect(retention.Snapshot().tickets.size() <= 256, "terminal ticket history is bounded");

    const auto checkpoint = ledger.ExportCheckpoint();
    Expect(!checkpoint.empty(), "checkpoint exports after a completed tick");
    auto restored = MakeSimulator(*preview.graph, *config.config);
    Expect(restored.ImportCheckpoint(checkpoint, &error), "checkpoint imports: " + error);
    Expect(restored.Snapshot().stateHash == ledger.Snapshot().stateHash, "checkpoint round-trip preserves state hash");
    Expect(
        restored.Snapshot().totalPopulation + 1 == initialPopulation,
        "checkpoint preserves a killed ticket's population reduction");
    Expect(
        FindTicket(restored.Snapshot(), zombiesim::walker::TicketState::Killed) != nullptr,
        "checkpoint preserves killed ticket state");
    auto corruptedCheckpoint = checkpoint;
    corruptedCheckpoint.back() ^= std::byte{1};
    Expect(!restored.ImportCheckpoint(corruptedCheckpoint, &error), "corrupt checkpoint is rejected");
    for (int tick = 0; tick < 12; ++tick) {
        const auto originalSnapshot = ledger.AdvanceOneTick();
        const auto restoredSnapshot = restored.AdvanceOneTick();
        Expect(originalSnapshot.stateHash == restoredSnapshot.stateHash, "restored simulation stays deterministic");
    }

    if (failures != 0) {
        return 1;
    }

    std::cout << "walker_core_tests passed\n";
    return 0;
}