cmake_minimum_required(VERSION 3.24)

project(zombiesim_world_viewer VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

set(ZMVIEW_JSON_INCLUDE_DIR "${CMAKE_BINARY_DIR}/third_party")
set(ZMVIEW_JSON_HEADER "${ZMVIEW_JSON_INCLUDE_DIR}/nlohmann/json.hpp")
if(NOT EXISTS "${ZMVIEW_JSON_HEADER}")
    file(MAKE_DIRECTORY "${ZMVIEW_JSON_INCLUDE_DIR}/nlohmann")
    file(
        DOWNLOAD
        "https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp"
        "${ZMVIEW_JSON_HEADER}"
        EXPECTED_HASH "SHA256=9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6"
        TLS_VERIFY ON
        STATUS ZMVIEW_JSON_DOWNLOAD_STATUS
    )
    list(GET ZMVIEW_JSON_DOWNLOAD_STATUS 0 ZMVIEW_JSON_DOWNLOAD_RESULT)
    if(NOT ZMVIEW_JSON_DOWNLOAD_RESULT EQUAL 0)
        list(GET ZMVIEW_JSON_DOWNLOAD_STATUS 1 ZMVIEW_JSON_DOWNLOAD_MESSAGE)
        message(FATAL_ERROR "Unable to download nlohmann/json: ${ZMVIEW_JSON_DOWNLOAD_MESSAGE}")
    endif()
endif()

set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES OFF CACHE BOOL "" FORCE)
set(CUSTOMIZE_BUILD OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    raylib
    URL "https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz"
    URL_HASH "SHA256=AEA98ECF5BC5C5E0B789A76DE0083A21A70457050EA4CC2AEC7566935F5E258E"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(raylib)

add_library(viewer_core STATIC
    src/keyvalues.cpp
    src/vpk.cpp
    src/materials.cpp
    src/vtf.cpp
    src/geometry.cpp
    src/scene.cpp
    src/studio.cpp
    src/hammer.cpp
)
target_include_directories(viewer_core PUBLIC src "${ZMVIEW_JSON_INCLUDE_DIR}")
target_compile_features(viewer_core PUBLIC cxx_std_20)

add_executable(zombiesim-world-viewer src/main.cpp)
# The viewer executable is written to the repository bin folder.
set_target_properties(zombiesim-world-viewer PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
target_link_libraries(zombiesim-world-viewer PRIVATE viewer_core raylib)

if(MSVC)
    target_compile_options(viewer_core PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(viewer_core PRIVATE -Wall -Wextra)
endif()
if(MINGW)
    target_link_options(zombiesim-world-viewer PRIVATE -static -static-libgcc -static-libstdc++)
endif()
