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

# `cmake --build <dir> --target conform`: the conformance corpus (parse, check, run, test) and the command
# fixtures, replayed against the ms built here, one `passed/total` line each (cmake/Conform.cmake).
# MS_CONFORM_ENFORCE=ON fails the target on any corpus difference; the command fixtures always must pass.
# `conform-commands` replays only the command fixtures (tests/conformance/commands).
option(MS_CONFORM_ENFORCE "Fail conform when a corpus phase has a difference" OFF)
function(ms_conform_target name only comment)
  add_custom_target(${name}
    COMMAND ${CMAKE_COMMAND} "-DMS=$<TARGET_FILE:ms-c>" "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DENFORCE=${MS_CONFORM_ENFORCE}" "-DONLY=${only}" -P "${CMAKE_SOURCE_DIR}/cmake/Conform.cmake"
    DEPENDS ms-c
    USES_TERMINAL
    COMMENT "${comment}")
endfunction()
ms_conform_target(conform "" "Replaying the conformance corpus and the command fixtures")
ms_conform_target(conform-commands commands "Replaying the command fixtures")
