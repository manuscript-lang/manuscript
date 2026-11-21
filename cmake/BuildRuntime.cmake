# Builds the runtime archives and runs the C unit tests for a target: what `cargo xtask runtime` and `cargo xtask c-test` did.
# Run it in script mode from the repository root:
#   cmake -P cmake/BuildRuntime.cmake                    libms_native.a (and libms_native_musl.a on Linux)
#   cmake -DMS_STATS=ON -P cmake/BuildRuntime.cmake      also libms_native_stats.a, the counting runtime
#   cmake -DMS_MODE=tests -P cmake/BuildRuntime.cmake    the C unit tests of this host's runtime target, run with ctest
# Archives land in target/ms-native (MS_OUT). The compiler for a target is `clang`, llvm-mingw's clang for Windows
# (`MS_MINGW`, else target/llvm-bundle/mingw) and musl-gcc for musl (`MS_MUSL_CC`). What to compile is decided by the CMake
# project at the root (CMakeLists.txt, cmake/); this file picks the compiler and the library folder for a target, configures
# the project with Ninja, and folds the objects it leaves into one archive.
cmake_minimum_required(VERSION 3.20)

if(NOT MS_ROOT)
  cmake_path(GET CMAKE_CURRENT_LIST_DIR PARENT_PATH MS_ROOT)
endif()
if(NOT MS_OUT)
  set(MS_OUT "${MS_ROOT}/target/ms-native")
endif()
if(NOT MS_MODE)
  set(MS_MODE runtime)
endif()

set(host_os "${CMAKE_HOST_SYSTEM_NAME}")
# The processor is not set in script mode.
if(host_os STREQUAL "Windows")
  set(arch "$ENV{PROCESSOR_ARCHITECTURE}")
else()
  execute_process(COMMAND uname -m OUTPUT_VARIABLE arch OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
endif()
if(arch STREQUAL "arm64" OR arch STREQUAL "ARM64")
  set(arch aarch64)
elseif(arch STREQUAL "AMD64" OR arch STREQUAL "x64")
  set(arch x86_64)
endif()

# The triple the runtime is built for on this host; empty where the platform takes its own target.
set(host_triple "")
if(host_os STREQUAL "Linux")
  set(host_triple "${arch}-unknown-linux-gnu")
elseif(host_os STREQUAL "Windows")
  set(host_triple "${arch}-pc-windows-gnullvm")
endif()

set(exe_suffix "")
if(host_os STREQUAL "Windows")
  set(exe_suffix ".exe")
endif()

# The C compiler for `triple`.
function(compiler_for triple out)
  if(triple MATCHES "windows")
    if(DEFINED ENV{MS_MINGW})
      set(mingw "$ENV{MS_MINGW}")
    else()
      set(mingw "${MS_ROOT}/target/llvm-bundle/mingw")
    endif()
    set(${out} "${mingw}/bin/${arch}-w64-mingw32-clang${exe_suffix}" PARENT_SCOPE)
  elseif(triple MATCHES "musl")
    if(DEFINED ENV{MS_MUSL_CC})
      set(${out} "$ENV{MS_MUSL_CC}" PARENT_SCOPE)
    else()
      set(${out} musl-gcc PARENT_SCOPE)
    endif()
  else()
    set(${out} clang PARENT_SCOPE)
  endif()
endfunction()

# The archiver for `triple`: llvm-mingw's for Windows, else `ar`.
function(archiver_for triple out)
  if(triple MATCHES "windows")
    compiler_for("${triple}" compiler)
    cmake_path(GET compiler PARENT_PATH bin)
    set(${out} "${bin}/llvm-ar${exe_suffix}" PARENT_SCOPE)
  else()
    set(${out} ar PARENT_SCOPE)
  endif()
endfunction()

# The folder holding the pinned C libraries for `triple` (include/, lib/lib*.a), built once per target by build.sh.
function(libs_prefix_for triple out)
  compiler_for("${triple}" compiler)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env MS_C_LIBS=pinned "CC=${compiler}" sh "${MS_ROOT}/runtime/third_party/build.sh" "${triple}"
    OUTPUT_VARIABLE prefix
    RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "build.sh failed (the C build needs cmake and ninja: `sh runtime/third_party/libs.sh install`)")
  endif()
  string(STRIP "${prefix}" prefix)
  # build.sh runs under MSYS2 on Windows and prints /d/a/x; CMake and the compiler read D:/a/x.
  if(host_os STREQUAL "Windows" AND prefix MATCHES "^/([A-Za-z])/(.*)$")
    string(TOUPPER "${CMAKE_MATCH_1}" drive)
    set(prefix "${drive}:/${CMAKE_MATCH_2}")
  endif()
  set(${out} "${prefix}" PARENT_SCOPE)
endfunction()

# Configures the project for `triple` in `build`: the runtime, plus the unit tests when `tests` is ON.
function(configure triple build stats tests)
  # The glibc process entry is only for the archive, not for the unit tests.
  if(tests)
    set(entry OFF)
  else()
    set(entry ON)
  endif()
  set(args -S "${MS_ROOT}" -B "${build}" -G Ninja -DMS_BUILD_COMPILER=OFF -DCMAKE_BUILD_TYPE=
           -DMS_BUILD_TESTS=${tests} -DMS_ALLOC_STATS=${stats} -DMS_PROCESS_ENTRY=${entry})
  archiver_for("${triple}" ar)
  if(IS_ABSOLUTE "${ar}")
    list(APPEND args "-DCMAKE_AR=${ar}")
  endif()
  compiler_for("${triple}" compiler)
  list(APPEND args "-DCMAKE_C_COMPILER=${compiler}")
  set(libs_triple "${triple}")
  if(triple)
    list(APPEND args "-DMS_TRIPLE=${triple}")
  elseif(host_os STREQUAL "Darwin")
    set(libs_triple "${arch}-apple-darwin")
  endif()
  libs_prefix_for("${libs_triple}" prefix)
  list(APPEND args -DMS_C_LIBS=prefix "-DMS_LIBS_PREFIX=${prefix}")
  if(triple MATCHES "windows")
    # The libraries are static archives; their headers say so only when told.
    list(APPEND args "-DMS_LIBS_DEFINES=NGHTTP2_STATICLIB\\;PCRE2_STATIC\\;CURL_STATICLIB")
  endif()
  # The build is the same wherever it runs: the caller's flags do not reach it.
  execute_process(COMMAND "${CMAKE_COMMAND}" -E env --unset=CFLAGS --unset=LDFLAGS "${CMAKE_COMMAND}" ${args}
                  COMMAND_ERROR_IS_FATAL ANY)
endfunction()

# Drops the debug sections the library objects carry. Without a strip tool the archive is kept as built. Windows keeps
# the archive whole: `llvm-strip` rewrites some members (the ring assembly objects) so that `ld` rejects the archive.
function(strip_debug archive)
  if(host_os STREQUAL "Windows")
    return()
  endif()
  if(host_os STREQUAL "Darwin")
    set(flag -S)
    set(tools llvm-strip strip)
  else()
    # GNU `strip` first: `llvm-strip --strip-debug` rewrites the GCC-built objects of `ring` (`.group` sections)
    # into files GNU ld refuses.
    set(flag --strip-debug)
    set(tools strip llvm-strip)
  endif()
  set(original "${archive}.unstripped")
  file(COPY_FILE "${archive}" "${original}")
  foreach(tool IN LISTS tools)
    execute_process(COMMAND "${tool}" "${flag}" "${archive}" RESULT_VARIABLE status OUTPUT_QUIET ERROR_QUIET)
    if(status EQUAL 0)
      file(REMOVE "${original}")
      return()
    endif()
    # A failed tool may have left a partial file: start the next one from the original.
    file(COPY_FILE "${original}" "${archive}")
  endforeach()
  file(REMOVE "${original}")
endfunction()

# Builds the C half of the runtime for `triple` and folds it into `archive`.
function(build_archive triple dir name stats)
  set(build "${MS_OUT}/${dir}/cmake")
  configure("${triple}" "${build}" ${stats} OFF)
  execute_process(COMMAND "${CMAKE_COMMAND}" --build "${build}" --target ms_runtime COMMAND_ERROR_IS_FATAL ANY)
  file(STRINGS "${build}/c-objects.txt" objects)
  list(FILTER objects EXCLUDE REGEX "^$")
  set(archive "${MS_OUT}/${name}")
  file(REMOVE "${archive}")
  archiver_for("${triple}" ar)
  if(host_os STREQUAL "Windows")
    # The folded library members overflow Windows' 32 KiB command line; llvm-ar reads a response file.
    set(list_file "${MS_OUT}/${dir}/objects.rsp")
    list(JOIN objects "\n" lines)
    file(WRITE "${list_file}" "${lines}")
    execute_process(COMMAND "${ar}" rcs "${archive}" "@${list_file}" COMMAND_ERROR_IS_FATAL ANY)
    file(REMOVE "${list_file}")
  else()
    execute_process(COMMAND "${ar}" rcs "${archive}" ${objects} COMMAND_ERROR_IS_FATAL ANY)
  endif()
  strip_debug("${archive}")
endfunction()

if(MS_MODE STREQUAL "tests")
  set(triple "${host_triple}")
  set(build "${MS_OUT}/c-tests/cmake-tests")
  configure("${triple}" "${build}" OFF ON)
  # `-k 0` keeps going past a failing file, so one run reports every compile error, not the first.
  execute_process(COMMAND "${CMAKE_COMMAND}" --build "${build}" -- -k 0 COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND ctest --test-dir "${build}" --output-on-failure --timeout 120 COMMAND_ERROR_IS_FATAL ANY)
  return()
endif()

# One CMake build per archive, run one after another (CMake started beside a running build also fails on Windows with
# `AssignProcessToJobObject: (50) The request is not supported`). The counting runtime differs from the others: its
# allocator counts live blocks.
build_archive("${host_triple}" build libms_native.a OFF)
if(MS_STATS)
  build_archive("${host_triple}" build-stats libms_native_stats.a ON)
endif()
if(host_os STREQUAL "Linux")
  build_archive("${arch}-unknown-linux-musl" build-musl libms_native_musl.a OFF)
endif()
