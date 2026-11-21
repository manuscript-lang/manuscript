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

# Compiler cache when installed (plan section 5).
find_program(MS_CCACHE ccache)
if(MS_CCACHE)
  set(CMAKE_C_COMPILER_LAUNCHER "${MS_CCACHE}")
endif()

enable_testing()
add_subdirectory(src)
