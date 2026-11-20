# The C compiler (compiler/): libms as one translation unit, the dump tools the differential scripts
# (compiler/tests/*-diff.sh) run, the compiler's unit tests, the driver and the `libmstool.a` that
# Manuscript tools link with `--link`. Executables land in <build>/compiler. Targets are named for the file:
# `cmake --build <build> --target ms_syntax_dump`. Adding a tool `compiler/tools/ms_<name>.c` needs no edit here;
# a unit test `compiler/tests/<name>_test.c` needs a line below.
if(MS_WINDOWS)
  return()
endif()
set(_c "${CMAKE_SOURCE_DIR}/compiler")
if(NOT MS_BUILD_RUNTIME)
  # libms hashes packages with libcrypto (project/packages.c); a build without the runtime has no MsLibs.cmake to name it.
  find_package(OpenSSL REQUIRED)
  set(MS_LIB_crypto_INCLUDES ${OPENSSL_INCLUDE_DIR})
  set(MS_LIB_crypto_LINK OpenSSL::Crypto)
endif()
set(_cflags -std=c11 -O1 -g -Wall -Wextra -Werror -Wno-format-truncation)
set(_clink "")
if(MS_SANITIZE)
  list(APPEND _cflags -fsanitize=address,undefined -fno-sanitize-recover=undefined)
  list(APPEND _clink -fsanitize=address,undefined)
endif()
set(_bin "${CMAKE_BINARY_DIR}/compiler")

# libms: compiler/src/libms.c includes every other source, so it is one object (static helpers must not share
# names). Tests and tools link that object.
add_library(ms_libms OBJECT "${_c}/src/libms.c")
target_include_directories(ms_libms PUBLIC "${_c}/include" "${_c}/src" "${CMAKE_SOURCE_DIR}/runtime/include" ${MS_LIB_crypto_INCLUDES})
target_compile_options(ms_libms PRIVATE ${_cflags})
set_target_properties(ms_libms PROPERTIES C_EXTENSIONS OFF)

# ms_compiler_exe(<name> <sources>... [WITH_LIBMS] [INCLUDES <dirs>] [TEST])
function(ms_compiler_exe name)
  cmake_parse_arguments(E "WITH_LIBMS;TEST;PLAIN" "" "INCLUDES" ${ARGN})
  set(_sources ${E_UNPARSED_ARGUMENTS})
  if(E_WITH_LIBMS)
    # libms lists directories through the OS layer, which a Manuscript program gets from the runtime archive.
    list(APPEND _sources $<TARGET_OBJECTS:ms_libms> "${CMAKE_SOURCE_DIR}/runtime/sys/posix/fs.c" "${CMAKE_SOURCE_DIR}/runtime/sys/posix/clock.c")
  endif()
  add_executable(${name} ${_sources})
  target_include_directories(${name} PRIVATE "${_c}/include" "${CMAKE_SOURCE_DIR}/runtime/include" ${E_INCLUDES})
  if(NOT E_PLAIN)
    target_compile_options(${name} PRIVATE ${_cflags})
    target_link_options(${name} PRIVATE ${_clink})
  else()
    target_compile_options(${name} PRIVATE -std=c11 -O1 -Wall -Wextra -Werror)
  endif()
  # libms hashes packages with libcrypto (project/packages.c).
  target_link_libraries(${name} PRIVATE m ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
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

# Unit tests of the checker and the driver; ctest runs them.
foreach(name types_test ownership_test recursion_test ty_algebra_test infer_test implements_test lower_scope_test project_path_test project_manifest_test project_load_test project_discover_test semver_test lock_test resolve_test graph_check_test install_test)
  ms_compiler_exe(${name} "${_c}/tests/${name}.c" WITH_LIBMS TEST)
endforeach()
ms_compiler_exe(std_embed_test "${_c}/tests/std_embed_test.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS TEST INCLUDES "${_c}/tools")
ms_compiler_exe(driver_test "${_c}/src/driver.c" "${_c}/tests/driver_test.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS TEST)
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

# The thin `ms` in front of the Rust one.
ms_compiler_exe(ms "${_c}/src/driver.c" "${_c}/tools/ms.c" $<TARGET_OBJECTS:ms_std_embed> WITH_LIBMS)

# Helpers of the differential scripts: the mutator and the effect graph generator need no libms.
ms_compiler_exe(mutate "${_c}/tests/mutate.c" PLAIN)
ms_compiler_exe(effect_graph_gen "${_c}/tests/effect_graph_gen.c" PLAIN)

# libmstool.a: libms plus the tool interface (compiler/include/ms/tool.h), the archive a Manuscript tool links
# with `--link`. No sanitizers: it links into programs built by `ms`.
add_library(ms_tool STATIC "${_c}/src/libms.c" "${_c}/src/tool.c")
target_include_directories(ms_tool PRIVATE "${_c}/include" "${CMAKE_SOURCE_DIR}/runtime/include"
                           "${CMAKE_SOURCE_DIR}/crates/ms-rt-abi/include" ${MS_LIB_crypto_INCLUDES})
target_compile_options(ms_tool PRIVATE -O1 -g -Wall -Wextra -Werror -Wno-format-truncation)
set_target_properties(ms_tool PROPERTIES OUTPUT_NAME mstool ARCHIVE_OUTPUT_DIRECTORY "${_bin}")

# libms_tools.a: libms plus the shim Manuscript `extern fn` declarations call (compiler/tools/tool_shim.c, which
# includes only ms_abi.h because its names collide with libms's). `make libms-tools` copies it to target/.
add_library(ms_tools_shim STATIC "${_c}/src/libms.c" "${_c}/tools/tool_shim.c")
set_source_files_properties("${_c}/src/libms.c" PROPERTIES INCLUDE_DIRECTORIES
                            "${_c}/include;${_c}/src;${CMAKE_SOURCE_DIR}/runtime/include;${MS_LIB_crypto_INCLUDES}")
set_source_files_properties("${_c}/tools/tool_shim.c" PROPERTIES INCLUDE_DIRECTORIES
                            "${CMAKE_SOURCE_DIR}/crates/ms-rt-abi/include")
target_compile_options(ms_tools_shim PRIVATE -O2)
set_target_properties(ms_tools_shim PROPERTIES OUTPUT_NAME ms_tools ARCHIVE_OUTPUT_DIRECTORY "${_bin}")
