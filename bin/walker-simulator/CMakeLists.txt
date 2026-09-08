cmake_minimum_required(VERSION 3.24)

project(zombiesim_walker_simulator VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)

find_package(nlohmann_json 3.11.3 CONFIG QUIET)
if(NOT nlohmann_json_FOUND)
    set(ZMWALKER_JSON_INCLUDE_DIR "${CMAKE_BINARY_DIR}/third_party")
    set(ZMWALKER_JSON_HEADER "${ZMWALKER_JSON_INCLUDE_DIR}/nlohmann/json.hpp")
    file(MAKE_DIRECTORY "${ZMWALKER_JSON_INCLUDE_DIR}/nlohmann")
    file(
        DOWNLOAD
        "https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp"
        "${ZMWALKER_JSON_HEADER}"
        EXPECTED_HASH "SHA256=9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"
        TLS_VERIFY ON
        STATUS ZMWALKER_JSON_DOWNLOAD_STATUS
    )
    list(GET ZMWALKER_JSON_DOWNLOAD_STATUS 0 ZMWALKER_JSON_DOWNLOAD_RESULT)
    if(NOT ZMWALKER_JSON_DOWNLOAD_RESULT EQUAL 0)
        list(GET ZMWALKER_JSON_DOWNLOAD_STATUS 1 ZMWALKER_JSON_DOWNLOAD_MESSAGE)
        message(FATAL_ERROR "Unable to download nlohmann/json: ${ZMWALKER_JSON_DOWNLOAD_MESSAGE}")
    endif()

    add_library(nlohmann_json INTERFACE)
    add_library(nlohmann_json::nlohmann_json ALIAS nlohmann_json)
    target_include_directories(nlohmann_json INTERFACE "${ZMWALKER_JSON_INCLUDE_DIR}")
endif()

add_library(walker_core STATIC
    src/command_log.cpp
    src/walker_config.cpp
    src/world_graph.cpp
    src/world_json_importer.cpp
    src/walker_simulator.cpp
)

target_include_directories(walker_core PUBLIC include)
target_link_libraries(walker_core PUBLIC nlohmann_json::nlohmann_json)
target_compile_features(walker_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(walker_core PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(walker_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
endif()

option(ZMWALKER_BUILD_OBSERVER "Build the standalone walker observer" ON)
if(ZMWALKER_BUILD_OBSERVER)
    add_executable(zombiesim-walker-observer src/observer/main.cpp)
    target_link_libraries(zombiesim-walker-observer PRIVATE walker_core)
    if(MINGW)
        target_link_options(zombiesim-walker-observer PRIVATE -static -static-libgcc -static-libstdc++)
    endif()
endif()

option(ZMWALKER_BUILD_GMOD_MODULE "Build the optional Garry's Mod server module" OFF)
if(ZMWALKER_BUILD_GMOD_MODULE)
    if(NOT WIN32)
        message(FATAL_ERROR "The initial GMod module target supports Windows only")
    endif()
    if(MINGW AND NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR "The MinGW GMod module target requires a 64-bit compiler")
    endif()

    add_subdirectory(third_party/gmod-module-base/include)
    add_library(
        zombiesimwalker
        SHARED
            src/gmod_adapter/module_server.cpp
            src/gmod_adapter/walker_worker.cpp
    )
    target_include_directories(zombiesimwalker SYSTEM PRIVATE third_party/gmod-module-base/include)
    target_link_libraries(zombiesimwalker PRIVATE walker_core gmod-module-base)
    if(MSVC)
        target_compile_options(zombiesimwalker PRIVATE /W4 /permissive- /EHsc)
    else()
        target_compile_options(zombiesimwalker PRIVATE -Wall -Wextra -Wpedantic -Wconversion)
    endif()
    if(MINGW)
        target_compile_definitions(zombiesimwalker PRIVATE _M_X64)
        target_link_options(zombiesimwalker PRIVATE -static -static-libgcc -static-libstdc++)
    endif()
    set_gmod_suffix_prefix(zombiesimwalker)
    set_target_properties(
        zombiesimwalker
        PROPERTIES
            OUTPUT_NAME "zombiesimwalker"
            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist"
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist"
    )
endif()

if(BUILD_TESTING)
    add_executable(walker_core_tests tests/walker_core_tests.cpp)
    target_link_libraries(walker_core_tests PRIVATE walker_core)
    if(MINGW)
        target_link_options(walker_core_tests PRIVATE -static -static-libgcc -static-libstdc++)
    endif()
    target_compile_definitions(
        walker_core_tests
        PRIVATE
            ZMWALKER_PREVIEW_WORLD_JSON="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/preview-world.json"
            ZMWALKER_CONFIG_JSON="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/walker-config-v1.json"
            ZMWALKER_COMMAND_LOG_JSONL="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/command-log-basic.jsonl"
            ZMWALKER_EXPECTED_HASHES_JSON="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/expected-state-hashes.json"
    )
    add_test(NAME walker_core_tests COMMAND walker_core_tests)
endif()