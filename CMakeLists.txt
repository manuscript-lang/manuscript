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
include(MsLld)

# Program links use lld without libgcc or compiler-rt, so no archive may call the out-of-line atomic helpers
# (`__aarch64_swp8_relax` and friends) that clang uses on Linux arm64 by default.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(MS_ATOMIC_FLAGS -mno-outline-atomics)
  string(APPEND CMAKE_C_FLAGS " -mno-outline-atomics")
endif()
# Generated code keeps a frame pointer and the fault walk follows the chain of saved ones, so the runtime keeps it in
# every preset: a Release archive without it ends a trace at the first runtime frame.
if(NOT MSVC)
  string(APPEND CMAKE_C_FLAGS " -fno-omit-frame-pointer")
endif()
# Windows gives a thread 1 MiB unless the executable asks for more, where Linux gives the main thread 8 MiB: a program
# whose checker and optimizer recurse through a 1500-term expression (the stack-overflow fixture) ended the compiler itself
# with 0xC00000FD. Every executable reserves 64 MiB (address space only; pages commit as they are used).
if(WIN32 AND NOT MSVC)
  add_link_options("LINKER:--stack,67108864")
endif()
# The counting runtime (live blocks, parks, copies) for the leak, cancel and count gates: `cmake --preset stats`.
option(MS_STATS "Compile the runtime's counters in" OFF)
if(MS_STATS)
  add_compile_definitions(MS_STATS=1)
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
foreach(layer compiler tooling lsp cli lint)
  include(targets/${layer})
endforeach()

# `cmake --build <dir> --target conform`: the conformance corpus (parse, check, run, test) and the command
# fixtures, replayed against the ms built here, one `passed/total` line each (cmake/Conform.cmake).
# MS_CONFORM_ENFORCE=ON fails the target on any corpus difference; the command fixtures always must pass.
# `conform-commands` replays only the command fixtures (tests/commands).
option(MS_CONFORM_ENFORCE "Fail conform when a corpus phase has a difference" OFF)
function(ms_conform_target name only comment)
  add_custom_target(${name}
    COMMAND ${CMAKE_COMMAND} "-DMS=$<TARGET_FILE:ms>" "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
      "-DENFORCE=${MS_CONFORM_ENFORCE}" "-DONLY=${only}" -P "${CMAKE_SOURCE_DIR}/cmake/Conform.cmake"
    DEPENDS ms
    USES_TERMINAL
    COMMENT "${comment}")
endfunction()
ms_conform_target(conform "" "Replaying the conformance corpus and the command fixtures")
ms_conform_target(conform-commands commands "Replaying the command fixtures")

# Downloads the pinned shared LLVM library (cmake/toolchain/llvm-lib.lock) and, in CI, exports MS_LLVM for the later steps
# (cmake/FetchLlvmLib.cmake). It does not need ms, so it can run before anything is built, on a machine with no LLVM.
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|ARM64|aarch64|AARCH64)$")
  set(MS_LLVM_ARCH arm64)
else()
  set(MS_LLVM_ARCH amd64)
endif()
add_custom_target(llvm-lib
  COMMAND ${CMAKE_COMMAND} "-DROOT=${CMAKE_SOURCE_DIR}" "-DARCH=${MS_LLVM_ARCH}" -P "${CMAKE_SOURCE_DIR}/cmake/FetchLlvmLib.cmake"
  USES_TERMINAL
)

# Downloads the pinned shared Cranelift library (cmake/toolchain/cranelift-lib.lock), which Debug builds use when present.
add_custom_target(cranelift-lib
  COMMAND ${CMAKE_COMMAND} "-DROOT=${CMAKE_SOURCE_DIR}" "-DARCH=${MS_LLVM_ARCH}" -P "${CMAKE_SOURCE_DIR}/cmake/FetchCraneliftLib.cmake"
  USES_TERMINAL
)

# Formatting, nested matches, release pins, workflow triggers and the license inventory (tools/repo-check.ms). The tool
# lists the files with git, which the MSYS2 shell of the Windows runners does not have on PATH: Git for Windows is.
find_program(MS_GIT git PATHS "$ENV{ProgramFiles}/Git/cmd")
add_custom_target(repo-check
  COMMAND ${CMAKE_COMMAND} -E env "MS=$<TARGET_FILE:ms>" "GIT=${MS_GIT}" $<TARGET_FILE:ms> run tools/repo-check.ms
  COMMAND ${CMAKE_COMMAND} -E env "MS=$<TARGET_FILE:ms>" "GIT=${MS_GIT}" $<TARGET_FILE:ms> run tools/repo-check.ms -- licenses --check
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  DEPENDS ms
  USES_TERMINAL
  COMMENT "Checking repository invariants")

# Ownership counts (tools/count-check.ms): builds the `stats` preset itself, runs tests/checks/ownership-counts in Debug
# and Release against it, and fails on a live block or a changed cleanup order.
add_custom_target(count-check
  COMMAND $<TARGET_FILE:ms> run tools/count-check.ms
  COMMAND ${CMAKE_COMMAND} -E env "MS=$<TARGET_FILE:ms>" $<TARGET_FILE:ms> run tools/count-check-selftest.ms
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  DEPENDS ms
  USES_TERMINAL
  COMMENT "Checking ownership counts")

# Every standard declaration and member has a description that passes the structural checks (tools/docgen.ms), and every
# embedded `manuscript` example still parses and checks (tools/example-check.ms), so a syntax change cannot leave one stale.
# `git` lists the files, as for repo-check.
add_custom_target(docs-check
  COMMAND ${CMAKE_COMMAND} -E env "MS=$<TARGET_FILE:ms>" $<TARGET_FILE:ms> run tools/docgen.ms -- --check
  COMMAND ${CMAKE_COMMAND} -E env "MS=$<TARGET_FILE:ms>" "GIT=${MS_GIT}" $<TARGET_FILE:ms> run tools/example-check.ms
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  DEPENDS ms
  USES_TERMINAL
  COMMENT "Checking standard-library descriptions and embedded examples")

