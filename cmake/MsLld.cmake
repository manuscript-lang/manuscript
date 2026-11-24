# Links every executable and shared library of this build with the pinned lld (cmake/toolchain/lld.lock): the same linker
# the programs ms builds are linked with, on every platform, in every preset. The release asset for the host is
# downloaded once per build directory and checked against the lock's digest; lld is one multi-call binary that picks its
# flavor from the name it is run as, so it is copied as `ld.lld` (ld64.lld on macOS), and the compiler driver is
# pointed at that copy. MS_SYSTEM_LINKER=ON keeps the compiler's own linker (a fallback for a host that cannot reach
# the release).
# MS_LLD_TOOL: the multi-call `lld` of this build tree, which a build-tree ms runs for the glibc stubs (src/cli/pipeline.c).
set(MS_LLD_TOOL "lld")
option(MS_SYSTEM_LINKER "Link ms with the compiler's own linker instead of the pinned lld" OFF)
if(MS_SYSTEM_LINKER OR MSVC)
  return()
endif()

file(STRINGS "${CMAKE_SOURCE_DIR}/cmake/toolchain/lld.lock" ms_lld_lock)
foreach(line IN LISTS ms_lld_lock)
  if(line MATCHES "^tag +(.+)$")
    set(ms_lld_tag "${CMAKE_MATCH_1}")
  elseif(line MATCHES "^version +(.+)$")
    set(ms_lld_version "${CMAKE_MATCH_1}")
  elseif(line MATCHES "^([0-9a-f]+) +([^ ]+)$")
    set(ms_lld_digest_of_${CMAKE_MATCH_2} "${CMAKE_MATCH_1}")
  endif()
endforeach()

string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" ms_lld_os)
if(ms_lld_os MATCHES "^(cygwin|msys|mingw)")
  set(ms_lld_os windows)
endif()
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
  set(ms_lld_arch arm64)
else()
  set(ms_lld_arch amd64)
endif()
set(ms_lld_asset "lld-${ms_lld_version}-${ms_lld_os}-${ms_lld_arch}.tar.gz")
if(NOT DEFINED ms_lld_digest_of_${ms_lld_asset})
  message(FATAL_ERROR "cmake/toolchain/lld.lock has no ${ms_lld_asset}")
endif()

set(ms_lld_dir "${CMAKE_BINARY_DIR}/lld")
set(ms_lld_suffix "")
set(ms_lld_name ld.lld)
if(ms_lld_os STREQUAL "windows")
  set(ms_lld_suffix ".exe")
elseif(ms_lld_os STREQUAL "darwin")
  set(ms_lld_name ld64.lld)
endif()
set(MS_LLD "${ms_lld_dir}/${ms_lld_name}${ms_lld_suffix}")
if(NOT EXISTS "${MS_LLD}")
  file(DOWNLOAD
    "https://github.com/manuscript-lang/llvm-bundle/releases/download/${ms_lld_tag}/${ms_lld_asset}"
    "${ms_lld_dir}/${ms_lld_asset}" EXPECTED_HASH SHA256=${ms_lld_digest_of_${ms_lld_asset}} STATUS ms_lld_result)
  list(GET ms_lld_result 0 ms_lld_code)
  if(NOT ms_lld_code EQUAL 0)
    message(FATAL_ERROR "cannot fetch ${ms_lld_asset}: ${ms_lld_result} (-DMS_SYSTEM_LINKER=ON uses the compiler's linker)")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${ms_lld_dir}/${ms_lld_asset}" DESTINATION "${ms_lld_dir}/extract")
  file(COPY_FILE "${ms_lld_dir}/extract/bin/lld${ms_lld_suffix}" "${MS_LLD}")
  file(CHMOD "${MS_LLD}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
endif()
set(MS_LLD_TOOL "${ms_lld_dir}/extract/bin/lld${ms_lld_suffix}")
# Only C links: a C++ compiler another part of the build enables is not necessarily clang.
add_link_options("$<$<LINK_LANGUAGE:C>:--ld-path=${MS_LLD}>")
message(STATUS "Linking with the pinned lld ${ms_lld_version}: ${MS_LLD}")
