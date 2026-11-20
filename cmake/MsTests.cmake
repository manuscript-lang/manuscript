# The C runtime unit tests (runtime/tests), run by ctest. With MS_SANITIZE=ON they build under AddressSanitizer
# and UBSan, as `make c-test` does. Only the POSIX layer is covered here; the Windows layer is covered by the
# conformance corpus on Windows.
if(MS_WINDOWS)
  return()
endif()
set(_tests "${CMAKE_SOURCE_DIR}/runtime/tests")
set(_rt "${CMAKE_SOURCE_DIR}/runtime")

set(_test_flags -O1 -g -Wall -Wextra -Werror)
set(_plain_flags -O0 -g -Wall -Wextra -Werror)
if(MS_SANITIZE)
  list(APPEND _test_flags -fsanitize=address,undefined -fno-sanitize-recover=undefined)
endif()

# Objects of a folder's sources, compiled once for every test that links them.
function(ms_test_objects name)
  add_library(${name} OBJECT ${ARGN})
  target_include_directories(${name} PRIVATE "${_rt}/include" "${_rt}/core" "${_rt}/std" "${_tests}/support")
  target_compile_options(${name} PRIVATE ${_test_flags})
  set_target_properties(${name} PROPERTIES C_EXTENSIONS ON POSITION_INDEPENDENT_CODE OFF)
endfunction()

# ms_test(<name> SOURCES <files>... [OBJECTS <object libraries>...] [LIBS <libs>...] [FLAGS <flags>...] [PLAIN])
# PLAIN builds without sanitizers, for a test that installs signal handlers of its own.
function(ms_test name)
  cmake_parse_arguments(T "PLAIN" "" "SOURCES;OBJECTS;LIBS;FLAGS;INCLUDES;DEFINES" ${ARGN})
  set(_flags ${_test_flags})
  if(T_PLAIN)
    set(_flags ${_plain_flags})
  endif()
  set(_objects "")
  foreach(o ${T_OBJECTS})
    list(APPEND _objects $<TARGET_OBJECTS:${o}>)
  endforeach()
  add_executable(${name} ${T_SOURCES} ${_objects})
  target_include_directories(${name} PRIVATE "${_rt}/include" "${_rt}/core" "${_rt}/std" "${_tests}/support" ${T_INCLUDES})
  target_compile_options(${name} PRIVATE ${_flags} ${T_FLAGS})
  target_compile_definitions(${name} PRIVATE ${T_DEFINES})
  target_link_options(${name} PRIVATE ${_flags})
  target_link_libraries(${name} PRIVATE ${T_LIBS})
  set_target_properties(${name} PROPERTIES C_EXTENSIONS ON RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests")
  add_test(NAME ${name} COMMAND ${name} WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endfunction()

file(GLOB _core_sources CONFIGURE_DEPENDS "${_rt}/core/*.c")
file(GLOB _posix_sources CONFIGURE_DEPENDS "${_rt}/sys/posix/*.c")
file(GLOB _support_sources CONFIGURE_DEPENDS "${_tests}/support/*.c")
file(GLOB _std_sources CONFIGURE_DEPENDS "${_rt}/std/*.c")
file(GLOB _std_support CONFIGURE_DEPENDS "${_tests}/std_support/*.c")
file(GLOB _io_sources CONFIGURE_DEPENDS "${_rt}/io/*.c")

# core_*: all of runtime/core and runtime/sys/posix, the allocator's live-block counts on.
# task_abi.c is linked by core_task_abi alone: the other tests stub the task ABI and run without a scheduler.
set(_task_abi "${_rt}/core/task_abi.c")
list(REMOVE_ITEM _core_sources "${_task_abi}")
ms_test_objects(ms_test_core ${_core_sources} ${_posix_sources} ${_support_sources})
target_compile_definitions(ms_test_core PRIVATE MS_ALLOC_STATS)
file(GLOB _core_tests CONFIGURE_DEPENDS "${_tests}/core_*.c")
foreach(file ${_core_tests})
  get_filename_component(name "${file}" NAME_WE)
  set(_extra "")
  if(name STREQUAL "core_task_abi")
    set(_extra "${_task_abi}")
  endif()
  ms_test(${name} SOURCES "${file}" ${_extra} OBJECTS ms_test_core LIBS m DEFINES MS_ALLOC_STATS)
endforeach()

# The OS layer: runtime/sys/posix and the portable thread.c over libuv. The fault test overflows a thread's stack, which
# the sanitizers' own signal handlers would intercept.
ms_test(sys_mem SOURCES "${_tests}/sys_mem.c" ${_posix_sources} LIBS)
ms_test(sys_thread SOURCES "${_tests}/sys_thread.c" "${_rt}/sys/thread.c" ${_posix_sources}
        INCLUDES ${MS_LIB_uv_INCLUDES} LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
ms_test(sys_fault SOURCES "${_tests}/sys_fault.c" "${_rt}/sys/thread.c" ${_posix_sources} PLAIN
        INCLUDES ${MS_LIB_uv_INCLUDES} LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})

# std_*: all of runtime/std with the system PCRE2, libcrypto and libuv.
file(GLOB _std_tests CONFIGURE_DEPENDS "${_tests}/std_*.c")
foreach(file ${_std_tests})
  get_filename_component(name "${file}" NAME_WE)
  ms_test(${name} SOURCES "${file}" ${_std_sources} ${_std_support} "${_rt}/sys/posix/fs.c" "${_rt}/sys/posix/clock.c"
          INCLUDES ${MS_LIB_pcre2_INCLUDES} ${MS_LIB_crypto_INCLUDES} ${MS_LIB_uv_INCLUDES}
          LIBS ${MS_LIB_pcre2_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK} m ${CMAKE_DL_LIBS})
endforeach()

# The HTTP/1 test links the vendored llhttp sources (the same ones the runtime archive compiles).
set(_llhttp "${CMAKE_SOURCE_DIR}/runtime/third_party/llhttp")
add_library(ms_test_llhttp OBJECT "${_llhttp}/src/api.c" "${_llhttp}/src/http.c" "${_llhttp}/src/llhttp.c")
target_include_directories(ms_test_llhttp PRIVATE "${_llhttp}/include")
target_compile_options(ms_test_llhttp PRIVATE -O1 -g -w)
if(MS_SANITIZE)
  target_compile_options(ms_test_llhttp PRIVATE -fsanitize=address,undefined -fno-sanitize-recover=undefined)
endif()
ms_test(http1_test SOURCES "${_tests}/http1_test.c" "${_rt}/net/http1.c" OBJECTS ms_test_llhttp
        INCLUDES "${_llhttp}/include")

# The reactor test links the reactor, libuv and the descriptor primitives of runtime/sys.
file(GLOB _io_tests CONFIGURE_DEPENDS "${_tests}/io_*.c")
list(FILTER _io_tests EXCLUDE REGEX "io_ring_test\\.c$")
foreach(file ${_io_tests})
  get_filename_component(name "${file}" NAME_WE)
  ms_test(${name} SOURCES "${file}" ${_io_sources} ${_posix_sources} INCLUDES ${MS_LIB_uv_INCLUDES}
          LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
endforeach()

# The socket layer: this platform's sources in runtime/sys (linux or darwin); the test needs only the C library.
string(TOLOWER "${CMAKE_SYSTEM_NAME}" _platform)
ms_test(sys_net_test SOURCES "${_tests}/sys_net_test.c" "${_rt}/sys/${_platform}/net.c")

# The completion ring has no dependency but the C library.
ms_test(io_ring_test SOURCES "${_tests}/io_ring_test.c" "${_rt}/io/ring.c")

# Smoke programs: each links the C libraries it names, so a wrong flag or a missing library shows here first.
set(_all_includes ${MS_LIB_uv_INCLUDES} ${MS_LIB_nghttp2_INCLUDES} ${MS_LIB_ssl_INCLUDES} ${MS_LIB_crypto_INCLUDES}
    ${MS_LIB_pcre2_INCLUDES} ${MS_LIB_z_INCLUDES} "${_llhttp}/include")
list(REMOVE_DUPLICATES _all_includes)
ms_test(clibs_smoke SOURCES "${_tests}/clibs_smoke.c" OBJECTS ms_test_llhttp INCLUDES ${_all_includes}
        LIBS ${MS_LIB_uv_LINK} ${MS_LIB_nghttp2_LINK} ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK}
             ${CMAKE_DL_LIBS})
ms_test(clibs_smoke_zlib SOURCES "${_tests}/clibs_smoke_zlib.c" INCLUDES ${MS_LIB_z_INCLUDES} LIBS ${MS_LIB_z_LINK})
ms_test(clibs_smoke_pcre2 SOURCES "${_tests}/clibs_smoke_pcre2.c" INCLUDES ${MS_LIB_pcre2_INCLUDES}
        LIBS ${MS_LIB_pcre2_LINK})
ms_test(tls_test SOURCES "${_tests}/tls_test.c" "${_rt}/net/tls.c" INCLUDES ${MS_LIB_ssl_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
ms_test(ws_test SOURCES "${_tests}/ws_test.c" "${_rt}/net/ws.c" INCLUDES ${MS_LIB_crypto_INCLUDES}
        LIBS ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
ms_test(conn_test SOURCES "${_tests}/conn_test.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" OBJECTS ms_test_llhttp
        INCLUDES "${_llhttp}/include")
ms_test(h2_test SOURCES "${_tests}/h2_test.c" "${_rt}/net/h2.c" INCLUDES ${MS_LIB_nghttp2_INCLUDES}
        LIBS ${MS_LIB_nghttp2_LINK})

# Fuzz harnesses (runtime/fuzz/*_fuzz.c): built always, run by `make c-fuzz` over runtime/fuzz/corpus/<name>
# (the driver takes -n <inputs> -s <seed> <files>; MS_FUZZER=libfuzzer builds coverage-guided ones instead).
set(MS_FUZZER "driver" CACHE STRING "driver, or libfuzzer (clang with the libFuzzer runtime)")
set(_fuzz_deps_http1 "${_rt}/net/http1.c")
set(_fuzz_deps_num "${_rt}/core/num.c")
file(GLOB _fuzzers CONFIGURE_DEPENDS "${_rt}/fuzz/*_fuzz.c")
foreach(file ${_fuzzers})
  get_filename_component(name "${file}" NAME_WE)
  string(REPLACE "_fuzz" "" short "${name}")
  if(NOT DEFINED _fuzz_deps_${short})
    message(FATAL_ERROR "runtime/fuzz/${name}.c has no dependency list in cmake/MsTests.cmake")
  endif()
  set(_objects "")
  if(short STREQUAL "http1")
    set(_objects ms_test_llhttp)
  endif()
  if(MS_FUZZER STREQUAL "libfuzzer")
    ms_test(${name} SOURCES "${file}" ${_fuzz_deps_${short}} OBJECTS ${_objects} INCLUDES "${_llhttp}/include"
            LIBS m FLAGS -fsanitize=fuzzer-no-link)
    target_link_options(${name} PRIVATE -fsanitize=fuzzer)
  else()
    ms_test(${name} SOURCES "${file}" "${_rt}/fuzz/driver.c" ${_fuzz_deps_${short}} OBJECTS ${_objects}
            INCLUDES "${_llhttp}/include" LIBS m)
  endif()
  set_property(TEST ${name} PROPERTY DISABLED TRUE)
endforeach()
