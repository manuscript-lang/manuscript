# Root build for the C implementation of Manuscript (see src/README.md).
# Everything C lives under src/; Rust stays in crates/ until it is deleted.
cmake_minimum_required(VERSION 3.25)
project(manuscript LANGUAGES C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(MsWarnings)
include(MsGlibcFloor)

# Program links use lld without libgcc or compiler-rt, so no archive may call the out-of-line atomic helpers
# (`__aarch64_swp8_relax` and friends) that clang uses on Linux arm64 by default.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(MS_ATOMIC_FLAGS -mno-outline-atomics)
  string(APPEND CMAKE_C_FLAGS " -mno-outline-atomics")
endif()
set(MS_MUSL_BUILD_DIR "${CMAKE_BINARY_DIR}/musl")

# Compiler cache when installed (plan section 5).
find_program(MS_CCACHE ccache)
if(MS_CCACHE)
  set(CMAKE_C_COMPILER_LAUNCHER "${MS_CCACHE}")
endif()

enable_testing()
add_subdirectory(src)
