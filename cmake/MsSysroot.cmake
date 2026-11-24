# Linux sysroots, fetched once at configure time and verified by hash (design/proposals/glibc-2-28-floor.md).
#
# glibc floor: Debian 10's `libc6-dev` and `linux-libc-dev` headers. The runtime is compiled against them so the
# objects name only symbols glibc 2.28 exports; the host's headers bind newer ones (`__isoc23_strtol`, the `fstat64`
# family). `-D__NO_INLINE__` keeps the headers from inlining `stat` over `__xstat`, which a modern libc no longer
# exports; the runtime defines the family for program links (src/runtime/sys/glibc_stat.c).
# musl: Alpine 3.20's `musl-dev` (headers, startup objects, libc.a), `linux-headers` and `llvm-libunwind-static`,
# for `--static` links. Its headers build the inner musl runtime (MS_LIBC=musl, see MsRuntimePackage.cmake).
#
# Sets MS_LIBC, MS_MUSL_SYSROOT and, on Linux, MS_LIBC_FLAGS (also appended to CMAKE_C_FLAGS).
set(MS_LIBC "glibc" CACHE STRING "The C library the Linux code is built for: glibc or musl")
set(MS_LIBC_FLAGS "")
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  return()
endif()

# Unpacks `<name>|<hash>` packages, copying <from> of each (a path inside the package) into <root>/<to>. A `.deb` holds a data.tar.xz.
function(ms_make_sysroot root url from to)
  if(EXISTS "${root}/.ready")
    return()
  endif()
  file(REMOVE_RECURSE "${root}")
  set(work "${root}/work")
  foreach(item IN LISTS ARGN)
    string(REPLACE "|" ";" item "${item}")
    list(GET item 0 name)
    list(GET item 1 hash)
    get_filename_component(file "${name}" NAME)
    file(MAKE_DIRECTORY "${work}")
    file(DOWNLOAD "${url}/${name}" "${work}/${file}" EXPECTED_HASH SHA256=${hash} STATUS status)
    list(GET status 0 code)
    if(NOT code EQUAL 0)
      message(FATAL_ERROR "sysroot: cannot fetch ${name}: ${status}")
    endif()
    execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf "${work}/${file}" WORKING_DIRECTORY "${work}" RESULT_VARIABLE code)
    if(file MATCHES "\\.deb$" AND code EQUAL 0)
      execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf "${work}/data.tar.xz" WORKING_DIRECTORY "${work}" RESULT_VARIABLE code)
    endif()
    if(NOT code EQUAL 0)
      message(FATAL_ERROR "sysroot: cannot unpack ${name}")
    endif()
    file(COPY "${work}/${from}" DESTINATION "${root}/${to}")
    file(REMOVE_RECURSE "${work}")
  endforeach()
  file(WRITE "${root}/.ready" "ok\n")
endfunction()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(ms_arch aarch64)
  set(ms_deb_arch arm64)
  set(ms_triple aarch64-linux-gnu)
  set(ms_glibc_hashes 04097716018288cef8b82339faa1a9847838b89f39574b5b169f4657da8bf269
                      e9a92d71d62655f673433c345a03fecaa4292f93c6572b28fd3d16dcfd1cc7f6)
  set(ms_musl_hashes 54c60103a486d0d54263289fd0bf89b490514e04b74d5228c346c78089d587e4
                     bc25332bdecc5327393b7cdb626d81250e17bcb387005ec6d52d3fa09b6cac1b
                     ebebd67c43a8b090c28d1ecfe36868f9747db260488e10b326386ba10323b4d5)
else()
  set(ms_arch x86_64)
  set(ms_deb_arch amd64)
  set(ms_triple x86_64-linux-gnu)
  set(ms_glibc_hashes 76b8413920d91a9a4289f99839933d0d30095e0ec12b05bb4f1a7f27e5ef4a55
                      c512f30f5abe413464b79ed23b54958df8cc104446c3ae93d83d28e23728a571)
  set(ms_musl_hashes e9cca1709f3a740976f22cc27b825261de062d97e7de2d08c41243017c389338
                     eac03f9d5ac52a86734f73bb444272aebf323e6dc03e9b69f87545f9da122f8a
                     821296243994f5ae4824db2bc2f09f860b10b044357d05e0582bdac017832a51)
endif()
list(GET ms_glibc_hashes 0 ms_libc_hash)
list(GET ms_glibc_hashes 1 ms_linux_hash)
list(GET ms_musl_hashes 0 ms_musl_hash)
list(GET ms_musl_hashes 1 ms_kernel_hash)
list(GET ms_musl_hashes 2 ms_unwind_hash)

set(MS_MUSL_SYSROOT "${CMAKE_BINARY_DIR}/musl-sysroot-${ms_arch}")
ms_make_sysroot("${MS_MUSL_SYSROOT}" "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/${ms_arch}" usr ""
  "musl-dev-1.2.5-r4.apk|${ms_musl_hash}" "linux-headers-6.6-r0.apk|${ms_kernel_hash}"
  "llvm-libunwind-static-17.0.6-r1.apk|${ms_unwind_hash}")

if(CMAKE_C_COMPILER_ID MATCHES "Clang")
  execute_process(COMMAND ${CMAKE_C_COMPILER} -print-resource-dir OUTPUT_VARIABLE ms_resource OUTPUT_STRIP_TRAILING_WHITESPACE)
  set(ms_builtin_headers "${ms_resource}/include")
else()
  execute_process(COMMAND ${CMAKE_C_COMPILER} -print-file-name=include OUTPUT_VARIABLE ms_builtin_headers OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

if(MS_LIBC STREQUAL "musl")
  set(MS_LIBC_FLAGS -nostdinc -isystem "${ms_builtin_headers}" -isystem "${MS_MUSL_SYSROOT}/usr/include")
else()
  set(glibc_root "${CMAKE_BINARY_DIR}/glibc-floor-${ms_deb_arch}")
  ms_make_sysroot("${glibc_root}" "https://archive.debian.org/debian/pool/main" usr/include usr
    "g/glibc/libc6-dev_2.28-10+deb10u1_${ms_deb_arch}.deb|${ms_libc_hash}"
    "l/linux/linux-libc-dev_4.19.249-2_${ms_deb_arch}.deb|${ms_linux_hash}")
  set(MS_LIBC_FLAGS -nostdinc -isystem "${ms_builtin_headers}" -isystem "${glibc_root}/usr/include/${ms_triple}"
    -isystem "${glibc_root}/usr/include" -D__NO_INLINE__)
endif()
string(REPLACE ";" " " ms_flags_text "${MS_LIBC_FLAGS}")
string(APPEND CMAKE_C_FLAGS " ${ms_flags_text}")
