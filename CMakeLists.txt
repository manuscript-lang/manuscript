# Root build of Manuscript (see src/README.md). All the code lives under src/, all the build rules under cmake/.
cmake_minimum_required(VERSION 3.25)
project(manuscript LANGUAGES C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(MsTarget)
include(MsSysroot)

# Program links use lld without libgcc or compiler-rt, so no archive may call the out-of-line atomic helpers
# (`__aarch64_swp8_relax` and friends) that clang uses on Linux arm64 by default.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(MS_ATOMIC_FLAGS -mno-outline-atomics)
  string(APPEND CMAKE_C_FLAGS " -mno-outline-atomics")
endif()
set(MS_MUSL_BUILD_DIR "${CMAKE_BINARY_DIR}/musl")

find_program(MS_CCACHE ccache)
if(MS_CCACHE)
  set(CMAKE_C_COMPILER_LAUNCHER "${MS_CCACHE}")
endif()

enable_testing()
# Every target is defined in cmake/targets/, one file per layer; src/ holds only sources (vendored libraries keep
# their own CMakeLists.txt there).
foreach(layer third_party base abi runtime)
  include(targets/${layer})
endforeach()
if(MS_LIBC STREQUAL "musl")
  return() # the inner build of the `--static` runtime holds the runtime archives only
endif()
foreach(layer compiler tooling cli lint)
  include(targets/${layer})
endforeach()

# `cmake --build <dir> --target conform-c` replays the whole conformance corpus against ms and prints the progress
# numbers; `conform-commands` replays only the command fixtures (tests/conformance/commands), for the platforms where
# the corpus is too slow. MS_ORACLE_DIR holds the oracle `ms-conform` built from 660429d4, outside the repository;
# MS_CONFORM_EXTRA adds ms-conform selection arguments, semicolon separated.
set(MS_ORACLE_DIR "$ENV{MS_ORACLE_DIR}" CACHE PATH "Directory with the oracle ms and ms-conform")
set(MS_CONFORM_EXTRA "" CACHE STRING "Extra ms-conform selection, semicolon separated")
function(ms_conform_target name only comment)
  add_custom_target(${name}
    COMMAND ${CMAKE_COMMAND}
      "-DMS_CONFORM=${MS_ORACLE_DIR}/ms-conform${CMAKE_EXECUTABLE_SUFFIX}"
      "-DMS_C=$<TARGET_FILE:ms>"
      "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DEXTRA=${MS_CONFORM_EXTRA}"
      "-DONLY=${only}"
      -P "${CMAKE_SOURCE_DIR}/cmake/ConformC.cmake"
    DEPENDS ms
    USES_TERMINAL
    COMMENT "${comment}")
endfunction()
ms_conform_target(conform-c "" "Running the conformance corpus against ms")
ms_conform_target(conform-commands commands "Replaying the command fixtures against ms")
