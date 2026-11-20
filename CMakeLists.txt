cmake_minimum_required(VERSION 3.20)
# The one build of every C part of Manuscript: the runtime archive, and the C tests that run against it.
# Generated with Ninja, cached with ccache when it is installed:
#   cmake -S . -B target/cmake/host -G Ninja && cmake --build target/cmake/host && ctest --test-dir target/cmake/host
# `make c-configure c-build c-test` wraps those. `cargo xtask runtime` and the `ms-rt` build script call the same
# project (runtime/build_c.rs) with MS_TRIPLE naming the target. Cache variables:
#   MS_TRIPLE      target triple of a runtime archive ("" = this host); picks the platform folders and flags.
#   MS_C_LIBS      system (pkg-config) or prefix (MS_LIBS_PREFIX holds include/ and lib/lib*.a: pinned builds, MSYS2).
#   MS_SANITIZE    ON: AddressSanitizer and UBSan (the tests).
#   MS_CCACHE      OFF: do not use ccache even when installed.
#   MS_ALLOC_STATS ON: the counting allocator (leak checks and the Rust unit tests).
#   MS_PROCESS_ENTRY ON: the archive programs link carries the glibc _start and the stat wrappers (glibc targets).
# Files are found by glob (CONFIGURE_DEPENDS), so adding a .c file under runtime/ needs no edit here.
project(manuscript C)

set(MS_TRIPLE "" CACHE STRING "Target triple of the runtime archive; empty for this host")
set(MS_C_LIBS "system" CACHE STRING "system or prefix")
set(MS_LIBS_PREFIX "" CACHE PATH "Folder with include/ and lib/ of the C libraries when MS_C_LIBS=prefix")
set(MS_LIBS_DEFINES "" CACHE STRING "Extra definitions for the libraries' headers")
option(MS_LIBS_IDIRAFTER "Search MS_LIBS_PREFIX/include after the compiler's own (MSYS2)" OFF)
option(MS_SANITIZE "Build the tests with AddressSanitizer and UBSan" OFF)
option(MS_CCACHE "Use ccache when installed" ON)
option(MS_ALLOC_STATS "Build the allocator as the counting runtime (live-block counts, scribbled frees)" OFF)
option(MS_PROCESS_ENTRY "Add the glibc process entry (_start, stat) to the runtime archive: programs link no crt1.o" OFF)
option(MS_BUILD_RUNTIME "Configure the runtime archive and its libraries" ON)
option(MS_BUILD_COMPILER "Configure the C compiler, its tools and tests (compiler/)" ON)
option(MS_BUILD_TESTS "Build the C runtime tests" ON)

if(MS_CCACHE AND NOT CMAKE_C_COMPILER_LAUNCHER)
  find_program(MS_CCACHE_PROGRAM ccache)
  if(MS_CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${MS_CCACHE_PROGRAM}")
  endif()
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(cmake/MsPlatform.cmake)
# The allocator of the runtime and of the compiler tools, so a build without the runtime has it too.
include(cmake/MsMimalloc.cmake)
if(MS_BUILD_RUNTIME)
  include(cmake/MsLibs.cmake)
  include(cmake/MsRuntime.cmake)
endif()
enable_testing()
if(MS_BUILD_RUNTIME AND MS_BUILD_TESTS)
  include(cmake/MsTests.cmake)
endif()
if(MS_BUILD_COMPILER)
  include(cmake/MsCompiler.cmake)
endif()
if(MS_BUILD_RUNTIME)
  include(cmake/MsLint.cmake)
endif()
