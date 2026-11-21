# Which platform the C is built for, from MS_TRIPLE (or this host): the runtime folders named for a platform
# (posix, linux, glibc, musl, darwin, windows) are compiled only for it.
if(MS_TRIPLE STREQUAL "")
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(_triple "unknown-linux-gnu")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_triple "apple-darwin")
  else()
    set(_triple "pc-windows-gnullvm")
  endif()
else()
  set(_triple "${MS_TRIPLE}")
endif()

set(MS_PLATFORM_DIRS "")
set(MS_WINDOWS OFF)
set(MS_MUSL OFF)
set(MS_GLIBC OFF)
if(_triple MATCHES "linux" OR _triple MATCHES "apple")
  list(APPEND MS_PLATFORM_DIRS posix)
endif()
if(_triple MATCHES "linux")
  list(APPEND MS_PLATFORM_DIRS linux)
endif()
if(_triple MATCHES "linux-gnu$")
  list(APPEND MS_PLATFORM_DIRS glibc)
  set(MS_GLIBC ON)
endif()
if(_triple MATCHES "musl")
  list(APPEND MS_PLATFORM_DIRS musl)
  set(MS_MUSL ON)
endif()
if(_triple MATCHES "apple")
  list(APPEND MS_PLATFORM_DIRS darwin)
endif()
if(_triple MATCHES "windows")
  list(APPEND MS_PLATFORM_DIRS windows)
  set(MS_WINDOWS ON)
endif()
set(MS_ALL_PLATFORM_DIRS posix linux glibc musl darwin windows)

# Whether the C libraries are wired for this target. Each target joins as its build is proven (workstream W0b);
# a source that needs a library the target lacks stays out of the archive and the Rust runtime serves it.
# A Windows host's own build (the unit tests of the Rust crates) targets MSVC and has no libraries yet.
if(_triple MATCHES "linux-(gnu|musl)$" OR _triple MATCHES "apple"
   OR (_triple MATCHES "windows-gnullvm$" AND NOT MS_TRIPLE STREQUAL ""))
  set(MS_LIBS_WIRED ON)
else()
  set(MS_LIBS_WIRED OFF)
endif()
# A target whose libraries are not all wired can still have some (a Windows MSVC host builds zlib for its unit
# tests): -DMS_LIBS_ONLY="z" names them, and the sources that need any other library stay out.
set(MS_LIBS_ONLY "" CACHE STRING "Libraries available on a target whose libraries are not all wired")

# Flags every runtime and test source gets (documentation/contributing/c-style.md has the warnings).
set(MS_C_FLAGS -fno-stack-protector
    # A null check stays even where an attribute says the pointer is never null.
    -fno-strict-aliasing -fno-delete-null-pointer-checks
    # A fault walks frame pointers to name the program line that called into the runtime, and the Rust runtime
    # is built with them (.cargo/config.toml), so C frames must keep theirs.
    -fno-omit-frame-pointer)
if(NOT MS_WINDOWS)
  # Windows objects are not position independent.
  list(APPEND MS_C_FLAGS -fPIC)
endif()
if(NOT MS_WINDOWS AND NOT MS_MUSL)
  # glibc and macOS check libc calls whose destination size is known. Level 2: its `__*_chk` entry points are
  # all older than the glibc floor.
  list(APPEND MS_C_FLAGS -D_FORTIFY_SOURCE=2)
endif()
if(_triple MATCHES "linux" AND (_triple MATCHES "^aarch64" OR (MS_TRIPLE STREQUAL "" AND CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")))
  # Newer compilers turn atomics into calls to libgcc's `__aarch64_ld*` helpers, which a program linked with lld
  # and no libgcc does not have; the runtime carries its atomics inline.
  include(CheckCCompilerFlag)
  check_c_compiler_flag(-mno-outline-atomics MS_HAS_NO_OUTLINE_ATOMICS)
  if(MS_HAS_NO_OUTLINE_ATOMICS)
    list(APPEND MS_C_FLAGS -mno-outline-atomics)
  endif()
endif()
# A compiler for a target other than this host's is told which: pass -DCMAKE_C_COMPILER_TARGET=<triple> on the first
# configure (`musl-gcc` already targets musl and llvm-mingw's clang wrapper mingw-w64, so they need none).
