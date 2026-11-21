# The C compiler (compiler/): libms as one translation unit, the dump tools the differential scripts
# (compiler/tests/*-diff.sh) run, the compiler's unit tests, the driver and the `libmstool.a` that
# Manuscript tools link with `--link`. Executables land in <build>/compiler. Targets are named for the file:
# `cmake --build <build> --target ms_syntax_dump`. Adding a tool `compiler/tools/ms_<name>.c` needs no edit here;
# a unit test `compiler/tests/<name>_test.c` needs a line below.
set(_c "${CMAKE_SOURCE_DIR}/compiler")

# libms_backend.a: what the Rust `ms` links to run the C back end in process (crates/ms-build/build.rs,
# compiler/include/ms/emit_program.h). No sanitizers, no project loader and the C library's allocator, so it
# brings no library of its own into `ms`.
add_library(ms_backend STATIC "${_c}/src/libms.c")
target_include_directories(ms_backend PRIVATE "${_c}/include" "${_c}/src" "${CMAKE_SOURCE_DIR}/runtime/include")
target_compile_definitions(ms_backend PRIVATE MS_LIBMS_NO_PROJECT)
if(MS_WINDOWS)
  # The Microsoft C library marks fopen and friends deprecated in favour of its own _s functions.
  target_compile_definitions(ms_backend PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
target_compile_options(ms_backend PRIVATE -O2 -Wall -Wextra -Werror -Wno-format-truncation -Wno-unknown-warning-option)
set_target_properties(ms_backend PROPERTIES C_EXTENSIONS OFF POSITION_INDEPENDENT_CODE ON ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/compiler")

# MS_BACKEND_ONLY: the Rust build wants libms_backend.a alone, so it does not need what the rest links (libcrypto,
# mimalloc).
if(MS_BACKEND_ONLY)
  return()
endif()
if(NOT MS_BUILD_RUNTIME)
  # libms hashes packages with libcrypto (project/packages.c) and runs programs through libuv (runtime/sys/spawn.c); a build
  # without the runtime has no MsLibs.cmake to name them: they are the pinned builds the runtime links, for this host
  # unless the caller names another folder with -DMS_LIBS_PREFIX.
  if(NOT MS_LIBS_PREFIX)
    include("${CMAKE_SOURCE_DIR}/cmake/MsPinnedLibs.cmake")
    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      set(_libs_triple "${CMAKE_SYSTEM_PROCESSOR}-apple-darwin")
    elseif(MS_WINDOWS)
      set(_libs_triple "${CMAKE_SYSTEM_PROCESSOR}-pc-windows-gnullvm")
    else()
      set(_libs_triple "${CMAKE_SYSTEM_PROCESSOR}-unknown-linux-gnu")
    endif()
    string(REPLACE "arm64" "aarch64" _libs_triple "${_libs_triple}")
    string(REPLACE "ARM64" "aarch64" _libs_triple "${_libs_triple}")
    string(REPLACE "AMD64" "x86_64" _libs_triple "${_libs_triple}")
    ms_pinned_libs_prefix("${_libs_triple}" "${CMAKE_C_COMPILER}" MS_LIBS_PREFIX)
  endif()
  set(MS_LIB_crypto_INCLUDES "${MS_LIBS_PREFIX}/include")
  set(MS_LIB_crypto_LINK "${MS_LIBS_PREFIX}/lib/libcrypto.a")
  set(MS_LIB_uv_INCLUDES "${MS_LIBS_PREFIX}/include")
  set(MS_LIB_uv_LINK "${MS_LIBS_PREFIX}/lib/libuv.a")
endif()
set(_cflags -std=c11 -O1 -g -Wall -Wextra -Werror -Wno-format-truncation)
set(_clink "")
if(MS_WINDOWS)
  list(APPEND _cflags -D_CRT_SECURE_NO_WARNINGS)
  # ms_mimalloc.h renames malloc and free, and the C library declares them dllimport (_ACRTIMP): the renamed mi_malloc
  # would then be an import. Declaring the C library's functions plain makes them link as ordinary symbols.
  list(APPEND _cflags -D_ACRTIMP= -D_DCRTIMP=)
  # __int128 division (constfold, range analysis) calls __divti3 and __modti3, which MSVC libraries lack: link the
  # compiler-rt builtins that ship with LLVM.
  execute_process(COMMAND "${CMAKE_C_COMPILER}" --rtlib=compiler-rt --print-libgcc-file-name
                  OUTPUT_VARIABLE _builtins OUTPUT_STRIP_TRAILING_WHITESPACE)
  message(STATUS "compiler-rt builtins: ${_builtins}")
  if(EXISTS "${_builtins}")
    list(APPEND _clink "${_builtins}")
  endif()
endif()
if(MS_SANITIZE)
  list(APPEND _cflags -fsanitize=address,undefined -fno-sanitize-recover=undefined)
  list(APPEND _clink -fsanitize=address,undefined)
endif()
set(_bin "${CMAKE_BINARY_DIR}/compiler")
# The compiler allocates with mimalloc, as the runtime does: ms_mimalloc.h is force-included into each source, and
# every executable links the allocator (libmstool.a and libms_tools.a link into programs that already carry the
# runtime's).
list(APPEND _cflags -include "${_c}/include/ms_mimalloc.h")
set(_mimalloc_include "${MS_MIMALLOC_DIR}/include")

# libms: compiler/src/libms.c includes every other source, so it is one object (static helpers must not share
# names). Tests and tools link that object.
add_library(ms_libms OBJECT "${_c}/src/libms.c")
target_include_directories(ms_libms PUBLIC "${_c}/include" "${_c}/src" "${CMAKE_SOURCE_DIR}/runtime/include" "${_mimalloc_include}" ${MS_LIB_crypto_INCLUDES})
target_compile_options(ms_libms PRIVATE ${_cflags})
set_target_properties(ms_libms PROPERTIES C_EXTENSIONS OFF)

# ms_compiler_exe(<name> <sources>... [WITH_LIBMS] [INCLUDES <dirs>] [TEST])
function(ms_compiler_exe name)
  cmake_parse_arguments(E "WITH_LIBMS;TEST;PLAIN" "" "INCLUDES" ${ARGN})
  set(_sources ${E_UNPARSED_ARGUMENTS})
  if(E_WITH_LIBMS)
    # libms lists directories through the OS layer, which a Manuscript program gets from the runtime archive.
    list(APPEND _sources $<TARGET_OBJECTS:ms_libms>)
    if(MS_WINDOWS)
      set(_os windows)
    else()
      set(_os posix)
    endif()
    list(APPEND _sources "${CMAKE_SOURCE_DIR}/runtime/sys/${_os}/fs.c")
    # Files by path, processes, the clock and the process id, over libuv: the same on every platform.
    list(APPEND _sources "${CMAKE_SOURCE_DIR}/runtime/sys/fs_path.c" "${CMAKE_SOURCE_DIR}/runtime/sys/spawn.c"
         "${CMAKE_SOURCE_DIR}/runtime/sys/libuv.c")
  endif()
  add_executable(${name} ${_sources})
  target_include_directories(${name} PRIVATE "${_c}/include" "${CMAKE_SOURCE_DIR}/runtime/include" "${_mimalloc_include}"
                             ${MS_LIB_uv_INCLUDES} ${E_INCLUDES})
  if(NOT E_PLAIN)
    target_compile_options(${name} PRIVATE ${_cflags})
    target_link_options(${name} PRIVATE ${_clink})
  else()
    target_compile_options(${name} PRIVATE -std=c11 -O1 -Wall -Wextra -Werror -include "${_c}/include/ms_mimalloc.h")
  endif()
  if(MS_WINDOWS)
    # No libm or libdl; libms hashes packages with libcrypto (project/packages.c) and allocates through the
    # force-included ms_mimalloc.h.
    target_link_libraries(${name} PRIVATE ms_mimalloc ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK})
    target_link_libraries(${name} PRIVATE ws2_32 iphlpapi userenv ole32 dbghelp advapi32 user32 shell32 psapi crypt32 bcrypt synchronization)
  else()
    target_link_libraries(${name} PRIVATE m ms_mimalloc ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
  endif()
  set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${_bin}")
  if(E_TEST)
    add_test(NAME ${name} COMMAND ${name} WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    set_tests_properties(${name} PROPERTIES LABELS compiler)
  endif()
endfunction()

# Dump tools: one per compiler/tools/ms_*.c, named for the file.
file(GLOB _tools CONFIGURE_DEPENDS "${_c}/tools/ms_*.c")
foreach(file ${_tools})
  get_filename_component(name "${file}" NAME_WE)
  ms_compiler_exe(${name} "${file}" WITH_LIBMS INCLUDES "${_c}/tools")
endforeach()

# Unit tests of the checker and the project loader; ctest runs them.
foreach(name types_test ownership_test recursion_test ty_algebra_test infer_test implements_test lower_scope_test project_path_test project_manifest_test project_load_test project_discover_test semver_test lock_test resolve_test graph_check_test install_test embed_test attach_test)
  ms_compiler_exe(${name} "${_c}/tests/${name}.c" WITH_LIBMS TEST)
endforeach()

# The embedded standard library: std_embed_gen writes std_embed_data.inc from stdlib/, std_embed.c includes it. Only
# the executables that load the library link ms_std_embed.
ms_compiler_exe(std_embed_gen "${_c}/tools/std_embed_gen.c" WITH_LIBMS INCLUDES "${_c}/tools")
file(GLOB_RECURSE _std_sources CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/stdlib/*.ms")
set(_std_data "${CMAKE_BINARY_DIR}/compiler/std_embed_data.inc")
add_custom_command(OUTPUT "${_std_data}" COMMAND std_embed_gen "${CMAKE_SOURCE_DIR}/stdlib" "${_std_data}"
                   DEPENDS std_embed_gen ${_std_sources} VERBATIM)
add_library(ms_std_embed OBJECT "${_c}/src/std_embed.c" "${_std_data}")
target_include_directories(ms_std_embed PRIVATE "${_c}/include" "${CMAKE_SOURCE_DIR}/runtime/include"
                           "${CMAKE_BINARY_DIR}/compiler")
target_compile_options(ms_std_embed PRIVATE -std=c11 -O1 -Wall -Wextra -Werror)

ms_compiler_exe(std_embed_test "${_c}/tests/std_embed_test.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS TEST INCLUDES "${_c}/tools")
ms_compiler_exe(package_check_test "${_c}/tests/package_check_test.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS TEST INCLUDES "${_c}/tools")

# The thin C driver in front of the Rust `ms` and the shell helpers of the differential scripts read the checkout the POSIX
# way; on Windows `ms` is the Manuscript front (tools/ms/main.ms over libmstool.a).
if(NOT MS_WINDOWS)
  ms_compiler_exe(driver_test "${_c}/src/driver.c" "${_c}/tests/driver_test.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS TEST)
  ms_compiler_exe(ms "${_c}/src/driver.c" "${_c}/tools/ms.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS)
  ms_compiler_exe(mutate "${_c}/tests/mutate.c" PLAIN)
  ms_compiler_exe(effect_graph_gen "${_c}/tests/effect_graph_gen.c" PLAIN)
endif()

# libmstool.a: libms plus the tool interface (compiler/include/ms/tool.h), the archive a Manuscript tool links
# with `--link`. No sanitizers: it links into programs built by `ms`.
file(STRINGS "${CMAKE_SOURCE_DIR}/.msversion" MS_VERSION_TEXT LIMIT_COUNT 1)
set_source_files_properties("${_c}/src/tool_build.c" PROPERTIES COMPILE_DEFINITIONS "MS_VERSION=\"${MS_VERSION_TEXT}\"")
add_library(ms_tool STATIC "${_c}/src/libms.c" "${_c}/src/tool.c" "${_c}/src/tool_check.c" "${_c}/src/tool_build.c" "${_c}/src/tool_search.c" "${_c}/src/tool_facts.c" $<TARGET_OBJECTS:ms_std_embed>)
target_include_directories(ms_tool PRIVATE "${_c}/include" "${CMAKE_SOURCE_DIR}/runtime/include"
                           "${CMAKE_SOURCE_DIR}/crates/ms-rt-abi/include" "${_mimalloc_include}" ${MS_LIB_crypto_INCLUDES})
target_compile_options(ms_tool PRIVATE -O1 -g -Wall -Wextra -Werror -Wno-format-truncation
                       -include "${_c}/include/ms_mimalloc.h")
set_target_properties(ms_tool PROPERTIES POSITION_INDEPENDENT_CODE ON OUTPUT_NAME mstool ARCHIVE_OUTPUT_DIRECTORY "${_bin}")

# libms_tools.a: libms plus the shim Manuscript `extern fn` declarations call (compiler/tools/tool_shim.c, which
# includes only ms_abi.h because its names collide with libms's). `make libms-tools` copies it to target/.
add_library(ms_tools_shim STATIC "${_c}/src/libms.c" "${_c}/tools/tool_shim.c")
set_source_files_properties("${_c}/src/libms.c" PROPERTIES INCLUDE_DIRECTORIES
                            "${_c}/include;${_c}/src;${CMAKE_SOURCE_DIR}/runtime/include;${_mimalloc_include};${MS_LIB_crypto_INCLUDES}"
                            COMPILE_OPTIONS "-include;${_c}/include/ms_mimalloc.h")
set_source_files_properties("${_c}/tools/tool_shim.c" PROPERTIES INCLUDE_DIRECTORIES
                            "${CMAKE_SOURCE_DIR}/crates/ms-rt-abi/include")
target_compile_options(ms_tools_shim PRIVATE -O2)
set_target_properties(ms_tools_shim PROPERTIES POSITION_INDEPENDENT_CODE ON OUTPUT_NAME ms_tools ARCHIVE_OUTPUT_DIRECTORY "${_bin}")
