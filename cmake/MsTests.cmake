# The C runtime unit tests (runtime/tests), run by ctest. With MS_SANITIZE=ON they build under AddressSanitizer
# and UBSan, as `make c-test` does. The OS layer under test is this platform's: runtime/sys/posix or runtime/sys/windows.
set(_tests "${CMAKE_SOURCE_DIR}/runtime/tests")
set(_rt "${CMAKE_SOURCE_DIR}/runtime")

# Frame pointers, as in every runtime build: the fault report walks them.
set(_test_flags -O1 -g -Wall -Wextra -Werror -fno-omit-frame-pointer)
set(_plain_flags -O0 -g -Wall -Wextra -Werror)
# Windows: MSYS2 keeps the libraries' headers in one prefix, searched after llvm-mingw's own (see MsRuntime.cmake).
set(_lib_compile "")
if(MS_LIBS_IDIRAFTER)
  set(_lib_compile -idirafter "${MS_LIBS_PREFIX}/include")
endif()
if(MS_SANITIZE)
  list(APPEND _test_flags -fsanitize=address,undefined -fno-sanitize-recover=undefined)
endif()

# Windows links the system libraries libuv, OpenSSL and the OS layer call into.
set(_syslibs "")
if(MS_WINDOWS)
  set(_syslibs ws2_32 iphlpapi userenv ole32 dbghelp advapi32 user32 shell32 psapi crypt32 bcrypt synchronization pthread)
endif()

# Tests written against POSIX descriptors (poll, pipe, mmap, fork, signals, uids) and not built on Windows yet. Each is
# a gap in Windows coverage tracked by issue #4888: the test moves onto the OS layer (ms_rt/sys.h), or a Windows twin
# is written, and its name leaves this list. Nothing else is skipped.
set(MS_POSIX_ONLY_TESTS
    core_alloc core_fault core_isolate core_pipe core_promise core_streams core_task core_workers core_sched_pool core_sched_abi core_stdout core_fault_abi
    conn_io_test dial_test h2_serve_test net_natives_test unix_test
    io_refused ws_socket_test exchange_test exchange_h2_test
    io_completion io_reactor sys_net_test std_signals std_process_state sys_fault)

# libcurl on macOS asks the system for proxy settings.
set(_curl_extra "")
if(APPLE)
  set(_curl_extra "-framework CoreFoundation" "-framework SystemConfiguration")
endif()

# Objects of a folder's sources, compiled once for every test that links them.
function(ms_test_objects name)
  add_library(${name} OBJECT ${ARGN})
  target_include_directories(${name} PRIVATE "${_rt}/include" "${_rt}/core" "${_rt}/std" "${_tests}/support"
                             "${MS_MIMALLOC_DIR}/include")
  target_compile_options(${name} PRIVATE ${_test_flags} ${_lib_compile})
  target_compile_definitions(${name} PRIVATE ${MS_LIBS_DEFINES})
  set_target_properties(${name} PROPERTIES C_EXTENSIONS ON POSITION_INDEPENDENT_CODE OFF)
endfunction()

# ms_test(<name> SOURCES <files>... [OBJECTS <object libraries>...] [LIBS <libs>...] [FLAGS <flags>...] [PLAIN])
# PLAIN builds without sanitizers, for a test that installs signal handlers of its own.
function(ms_test name)
  if(MS_WINDOWS AND name IN_LIST MS_POSIX_ONLY_TESTS)
    return()
  endif()
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
  target_compile_options(${name} PRIVATE ${_flags} ${_lib_compile} ${T_FLAGS})
  target_compile_definitions(${name} PRIVATE ${T_DEFINES} ${MS_LIBS_DEFINES})
  target_link_options(${name} PRIVATE ${_flags})
  target_link_libraries(${name} PRIVATE ${T_LIBS} ${_syslibs} ms_mimalloc)
  set_target_properties(${name} PROPERTIES C_EXTENSIONS ON RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests")
  add_test(NAME ${name} COMMAND ${name} WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  if(MS_SANITIZE AND NOT T_PLAIN)
    # ASan does not know the scheduler's stack switches, so a libc call on a task stack can trip over stale poison;
    # mimalloc's purge reads the clock on such a stack. Tests do not need freed memory returned to the OS.
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "MIMALLOC_PURGE_DELAY=-1")
  endif()
endfunction()

file(GLOB _core_sources CONFIGURE_DEPENDS "${_rt}/core/*.c")
if(MS_WINDOWS)
  set(_os windows)
  set(_pthread pthread) # winpthreads
else()
  set(_os posix)
  set(_pthread pthread)
endif()
file(GLOB _os_sources CONFIGURE_DEPENDS "${_rt}/sys/${_os}/*.c")
string(TOLOWER "${CMAKE_SYSTEM_NAME}" _platform)
# The Linux and macOS socket layer is its own file; on Windows sys/windows/net.c is already one of _os_sources.
set(_platform_net "${_rt}/sys/${_platform}/net.c")
set(_win_std_extra "")
if(MS_WINDOWS)
  set(_platform_net "")
  set(_win_std_extra "${_rt}/sys/windows/yield.c") # the Windows stream layer yields while it waits
endif()
file(GLOB _support_sources CONFIGURE_DEPENDS "${_tests}/support/*.c")
file(GLOB _std_sources CONFIGURE_DEPENDS "${_rt}/std/*.c")
# The JSON natives call the real maps, lists and number formatting of runtime/core, which the std tests fake.
file(GLOB _json_sources CONFIGURE_DEPENDS "${_rt}/std/json_*.c")
list(REMOVE_ITEM _std_sources ${_json_sources})
# The blocking pool needs a scheduler to park on; the std tests stub it (tests/std_support).
list(REMOVE_ITEM _std_sources "${_rt}/std/pool.c")
file(GLOB _std_support CONFIGURE_DEPENDS "${_tests}/std_support/*.c")
file(GLOB _io_sources CONFIGURE_DEPENDS "${_rt}/io/*.c")

# core_*: all of runtime/core and this platform's runtime/sys layer, the allocator's live-block counts on.
# task_abi.c is linked by core_task_abi alone: the other tests stub the task ABI and run without a scheduler.
set(_task_abi "${_rt}/core/task_abi.c")
# fault_abi.c is linked by core_fault_abi alone: the other tests use the weak fault stubs of tests/support.
set(_fault_abi "${_rt}/core/fault_abi.c")
list(REMOVE_ITEM _core_sources "${_task_abi}" "${_fault_abi}")
# The scheduler hooks of the tests (support/sched_env.c) poll descriptors, so they are POSIX-only for now.
if(MS_WINDOWS)
  list(FILTER _support_sources EXCLUDE REGEX "sched_env\\.c$")
else()
  list(FILTER _support_sources EXCLUDE REGEX "sched_pipe_stubs_win\\.c$")
endif()
# The pipe calls the Windows streams make into the scheduler, stubbed for tests that run one task on no reactor.
set(_pipe_stubs "")
if(MS_WINDOWS)
  set(_pipe_stubs "${_tests}/support/sched_pipe_stubs_win.c")
endif()
ms_test_objects(ms_test_core ${_core_sources} ${_os_sources} "${_rt}/sys/strtod.c" ${_support_sources})
target_compile_definitions(ms_test_core PRIVATE MS_ALLOC_STATS)
file(GLOB _core_tests CONFIGURE_DEPENDS "${_tests}/core_*.c")
foreach(file ${_core_tests})
  get_filename_component(name "${file}" NAME_WE)
  set(_extra "")
  set(_libs m)
  set(_include "")
  if(name STREQUAL "core_task_abi")
    set(_extra "${_task_abi}")
  elseif(name STREQUAL "core_fault_abi")
    set(_extra "${_fault_abi}")
  elseif(name STREQUAL "core_sched_pool")
    # The blocking pool (runtime/std/pool.c) over the real scheduler and task ABI, with libuv's threads.
    set(_extra "${_task_abi}" "${_rt}/std/pool.c")
    set(_include ${MS_LIB_uv_INCLUDES})
    set(_libs ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS} m)
  endif()
  ms_test(${name} SOURCES "${file}" ${_extra} OBJECTS ms_test_core INCLUDES ${_include} LIBS ${_libs} DEFINES MS_ALLOC_STATS)
endforeach()

# The OS layer: runtime/sys/<platform> and the portable thread.c over libuv. The fault test overflows a thread's stack, which
# the sanitizers' own signal handlers would intercept.
# On Windows the sampler in the OS layer allocates and spawns a thread, so the test links the core objects (the allocator and
# the thread stub) and not the OS sources a second time.
if(MS_WINDOWS)
  ms_test(sys_mem SOURCES "${_tests}/sys_mem.c" OBJECTS ms_test_core LIBS m)
else()
  ms_test(sys_mem SOURCES "${_tests}/sys_mem.c" ${_os_sources} LIBS)
endif()
ms_test(sys_mem_x86 SOURCES "${_tests}/sys_mem_x86.c" "${_rt}/sys/mem_x86.c" LIBS)
ms_test(sys_thread SOURCES "${_tests}/sys_thread.c" "${_rt}/sys/thread.c" ${_os_sources}
        INCLUDES ${MS_LIB_uv_INCLUDES} LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
ms_test(sys_sampler SOURCES "${_tests}/sys_sampler.c" "${_rt}/sys/thread.c" ${_os_sources}
        INCLUDES ${MS_LIB_uv_INCLUDES} LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
ms_test(sys_fault SOURCES "${_tests}/sys_fault.c" "${_rt}/sys/thread.c" ${_os_sources} PLAIN
        INCLUDES ${MS_LIB_uv_INCLUDES} LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})

# std_*: all of runtime/std with the system PCRE2, libcrypto, libuv and zlib.
file(GLOB _std_tests CONFIGURE_DEPENDS "${_tests}/std_*.c")
foreach(file ${_std_tests})
  get_filename_component(name "${file}" NAME_WE)
  ms_test(${name} SOURCES "${file}" ${_std_sources} ${_std_support} ${_pipe_stubs} "${_rt}/core/utf8.c" "${_rt}/sys/${_os}/fs.c" "${_rt}/sys/${_os}/clock.c" "${_rt}/sys/${_os}/fd.c"
          "${_rt}/sys/${_os}/ifindex.c" "${_rt}/sys/${_os}/process.c" "${_rt}/sys/${_os}/signal.c" ${_win_std_extra}
          INCLUDES ${MS_LIB_pcre2_INCLUDES} ${MS_LIB_crypto_INCLUDES} ${MS_LIB_uv_INCLUDES} ${MS_LIB_z_INCLUDES}
          LIBS ${MS_LIB_pcre2_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK} ${MS_LIB_z_LINK} m ${CMAKE_DL_LIBS})
endforeach()

# The JSON test replays the recorded corpus against the natives over the real runtime/core.
ms_test(json_test SOURCES "${_tests}/json_test.c" ${_json_sources} OBJECTS ms_test_core LIBS m DEFINES MS_ALLOC_STATS)

# The HTTP/1 test links the vendored llhttp sources (the same ones the runtime archive compiles).
set(_llhttp "${CMAKE_SOURCE_DIR}/runtime/third_party/llhttp")
ms_test_objects(ms_test_task_sleep "${_tests}/net_doubles/task_sleep.c")
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
  ms_test(${name} SOURCES "${file}" ${_io_sources} ${_os_sources} INCLUDES ${MS_LIB_uv_INCLUDES}
          LIBS ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS})
endforeach()

# The process entry: core, the reactor, the stop thread and the entry sources, with the std layer's stdout stubbed by the test.
file(GLOB _entry_sources CONFIGURE_DEPENDS "${_rt}/entry/*.c")
file(GLOB _entry_tests CONFIGURE_DEPENDS "${_tests}/entry_*.c")
foreach(file ${_entry_tests})
  get_filename_component(name "${file}" NAME_WE)
  ms_test(${name} SOURCES "${file}" ${_entry_sources} ${_io_sources} OBJECTS ms_test_core
          INCLUDES ${MS_LIB_uv_INCLUDES} LIBS m ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS} DEFINES MS_ALLOC_STATS)
endforeach()

# The socket layer: this platform's sources in runtime/sys (linux or darwin); the test needs only the C library.
ms_test(sys_net_test SOURCES "${_tests}/sys_net_test.c" ${_platform_net})

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
ms_test(x509_test SOURCES "${_tests}/x509_test.c" "${_rt}/net/x509.c" INCLUDES ${MS_LIB_crypto_INCLUDES}
        LIBS ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
ms_test(ws_test SOURCES "${_tests}/ws_test.c" "${_rt}/net/ws.c" INCLUDES ${MS_LIB_crypto_INCLUDES}
        LIBS ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
ms_test(ws_codec_test SOURCES "${_tests}/ws_codec_test.c" "${_rt}/net/ws_codec.c" "${_rt}/net/ws.c" OBJECTS ms_test_core
        INCLUDES ${MS_LIB_crypto_INCLUDES} ${MS_LIB_z_INCLUDES}
        LIBS ${MS_LIB_crypto_LINK} ${MS_LIB_z_LINK} ${CMAKE_DL_LIBS} m DEFINES MS_ALLOC_STATS)
ms_test(ws_socket_test SOURCES "${_tests}/ws_socket_test.c" "${_rt}/net/ws_socket.c" "${_rt}/net/ws_handle.c" "${_rt}/net/ws_codec.c" "${_rt}/net/ws.c"
        "${_rt}/net/conn_object.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_z_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_z_LINK} ${CMAKE_DL_LIBS} pthread m DEFINES MS_ALLOC_STATS)
ms_test(ws_dial_test SOURCES "${_tests}/ws_dial_test.c" "${_rt}/net/ws_dial.c" "${_rt}/net/ws_connect.c" "${_rt}/net/ws_socket_natives.c" "${_rt}/net/status.c" "${_rt}/net/ws_handle.c" "${_rt}/net/ws_client.c" "${_rt}/net/ws_socket.c"
        "${_rt}/net/ws_codec.c" "${_rt}/net/ws.c" "${_rt}/net/headers.c"
        "${_rt}/net/conn_object.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_z_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_z_LINK} ${CMAKE_DL_LIBS} pthread m DEFINES MS_ALLOC_STATS)
ms_test(ws_server_test SOURCES "${_tests}/ws_server_test.c" "${_rt}/net/ws_server.c" "${_rt}/net/ws_handle.c" "${_rt}/net/ws_socket.c"
        "${_rt}/net/ws_codec.c" "${_rt}/net/ws.c" "${_rt}/net/headers.c" "${_rt}/net/status.c"
        "${_rt}/net/conn_object.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_z_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_z_LINK} ${CMAKE_DL_LIBS} pthread m DEFINES MS_ALLOC_STATS)
ms_test(ws_client_test SOURCES "${_tests}/ws_client_test.c" "${_rt}/net/ws_client.c" "${_rt}/net/ws.c" "${_rt}/net/http1.c"
        OBJECTS ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_crypto_INCLUDES}
        LIBS ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS})
ms_test(conn_test SOURCES "${_tests}/conn_test.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" OBJECTS ms_test_llhttp
        INCLUDES "${_llhttp}/include")
ms_test(conn_io_test SOURCES "${_tests}/conn_io_test.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c"
        "${_rt}/net/tls.c" ${_platform_net} "${_rt}/sys/${_os}/clock.c" OBJECTS ms_test_task_sleep ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK}
        ${CMAKE_DL_LIBS} ${_pthread})
ms_test(addr_text_test SOURCES "${_tests}/addr_text_test.c" "${_rt}/net/addr_text.c")
ms_test(dial_test SOURCES "${_tests}/dial_test.c" "${_rt}/net/dial.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c"
        "${_rt}/net/http1.c" "${_rt}/net/tls.c" ${_platform_net} ${_io_sources} ${_os_sources}
        OBJECTS ms_test_task_sleep ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_uv_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS} ${_pthread})
ms_test(net_filter_test SOURCES "${_tests}/net_filter_test.c" "${_rt}/net/net_filter.c" "${_rt}/net/addr_text.c")
ms_test(net_natives_test SOURCES "${_tests}/net_natives_test.c" "${_rt}/net/datagram.c" "${_rt}/net/dns.c" "${_rt}/net/dns_query.c" "${_rt}/net/scope.c" "${_rt}/net/natives.c" "${_rt}/net/tls_conn.c" "${_rt}/net/server_natives.c" "${_rt}/net/listener.c" "${_rt}/net/status.c" "${_rt}/net/fetch.c" "${_rt}/net/dns.c" "${_rt}/net/dns_query.c"
        "${_rt}/net/headers.c" "${_rt}/net/curl_client.c" "${_rt}/net/net_filter.c" "${_rt}/net/conn_object.c" "${_rt}/net/addr_text.c"
        "${_rt}/net/dial.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        "${_rt}/sys/thread.c" ${_platform_net} ${_io_sources} ${_os_sources}
        OBJECTS ms_test_task_sleep ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_uv_INCLUDES} ${MS_LIB_curl_INCLUDES}
        LIBS ${MS_LIB_curl_LINK} ${_curl_extra} ${MS_LIB_nghttp2_LINK} ${MS_LIB_z_LINK} ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${MS_LIB_uv_LINK} ${CMAKE_DL_LIBS} ${_pthread})
ms_test(datagram_test SOURCES "${_tests}/datagram_test.c" "${_rt}/net/datagram.c" "${_rt}/net/status.c" "${_rt}/net/addr_text.c"
        "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c" ${_platform_net}
        OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS} ${_pthread} m)
ms_test(dns_test SOURCES "${_tests}/dns_test.c" "${_rt}/net/dns.c" "${_rt}/net/dns_query.c" "${_rt}/net/status.c"
        "${_rt}/net/addr_text.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS} ${_pthread} m)
ms_test(ip_test SOURCES "${_tests}/ip_test.c" "${_rt}/net/ip.c" "${_rt}/net/addr_text.c" OBJECTS ms_test_core LIBS m)
ms_test(unix_test SOURCES "${_tests}/unix_test.c" "${_rt}/net/unix.c" "${_rt}/net/listener.c" "${_rt}/net/server_natives.c"
        "${_rt}/net/status.c" "${_rt}/net/conn_object.c" "${_rt}/net/addr_text.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c"
        "${_rt}/net/http1.c" "${_rt}/net/tls.c" ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp
        INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES}
        LIBS ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS} ${_pthread} m)
ms_test(exchange_test SOURCES "${_tests}/exchange_test.c" "${_rt}/net/exchange.c" "${_rt}/net/exchange_h2.c" "${_rt}/net/h2_serve.c"
        "${_rt}/net/h2conn.c" "${_rt}/net/h2.c" "${_rt}/net/status.c" "${_rt}/net/headers.c"
        "${_rt}/net/conn_object.c" "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c"
        ${_platform_net} OBJECTS ms_test_task_sleep ms_test_core ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES}
        ${MS_LIB_nghttp2_INCLUDES} LIBS ${MS_LIB_nghttp2_LINK} ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS} ${_pthread} m)
ms_test(h2_test SOURCES "${_tests}/h2_test.c" "${_rt}/net/h2.c" INCLUDES ${MS_LIB_nghttp2_INCLUDES}
        LIBS ${MS_LIB_nghttp2_LINK})
ms_test(h2_serve_test SOURCES "${_tests}/h2_serve_test.c" "${_rt}/net/h2_serve.c" "${_rt}/net/h2conn.c" "${_rt}/net/h2.c"
        "${_rt}/net/conn_io.c" "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c" ${_platform_net}
        "${_rt}/sys/${_os}/clock.c" OBJECTS ms_test_task_sleep ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES}
        ${MS_LIB_nghttp2_INCLUDES} LIBS ${MS_LIB_nghttp2_LINK} ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS}
        ${_pthread})
ms_test(exchange_h2_test SOURCES "${_tests}/exchange_h2_test.c" "${_rt}/net/exchange_h2.c" "${_rt}/net/exchange.c" "${_rt}/net/conn_object.c" "${_rt}/net/headers.c"
        "${_rt}/net/h2_serve.c" "${_rt}/net/h2conn.c" "${_rt}/net/h2.c" "${_rt}/net/conn_io.c"
        "${_rt}/net/conn.c" "${_rt}/net/http1.c" "${_rt}/net/tls.c" ${_platform_net} "${_rt}/sys/${_os}/clock.c"
        OBJECTS ms_test_task_sleep ms_test_llhttp INCLUDES "${_llhttp}/include" ${MS_LIB_ssl_INCLUDES} ${MS_LIB_nghttp2_INCLUDES}
        LIBS ${MS_LIB_nghttp2_LINK} ${MS_LIB_ssl_LINK} ${MS_LIB_crypto_LINK} ${CMAKE_DL_LIBS} ${_pthread})
ms_test(h2conn_test SOURCES "${_tests}/h2conn_test.c" "${_rt}/net/h2conn.c" "${_rt}/net/h2.c"
        INCLUDES ${MS_LIB_nghttp2_INCLUDES} LIBS ${MS_LIB_nghttp2_LINK})

# Fuzz harnesses (runtime/fuzz/*_fuzz.c): built always, run by `make c-fuzz` over runtime/fuzz/corpus/<name>
# (the driver takes -n <inputs> -s <seed> <files>; MS_FUZZER=libfuzzer builds coverage-guided ones instead).
set(MS_FUZZER "driver" CACHE STRING "driver, or libfuzzer (clang with the libFuzzer runtime)")
set(_fuzz_deps_http1 "${_rt}/net/http1.c")
set(_fuzz_deps_num "${_rt}/core/num.c")
set(_fuzz_deps_h2conn "${_rt}/net/h2conn.c" "${_rt}/net/h2.c")
file(GLOB _fuzzers CONFIGURE_DEPENDS "${_rt}/fuzz/*_fuzz.c")
foreach(file ${_fuzzers})
  get_filename_component(name "${file}" NAME_WE)
  string(REPLACE "_fuzz" "" short "${name}")
  if(NOT DEFINED _fuzz_deps_${short})
    message(FATAL_ERROR "runtime/fuzz/${name}.c has no dependency list in cmake/MsTests.cmake")
  endif()
  set(_objects "")
  set(_fuzz_libs m)
  set(_fuzz_includes "${_llhttp}/include")
  if(short STREQUAL "http1")
    set(_objects ms_test_llhttp)
  elseif(short STREQUAL "h2conn")
    set(_fuzz_libs ${MS_LIB_nghttp2_LINK} m)
    set(_fuzz_includes ${MS_LIB_nghttp2_INCLUDES})
  endif()
  if(MS_FUZZER STREQUAL "libfuzzer")
    ms_test(${name} SOURCES "${file}" ${_fuzz_deps_${short}} OBJECTS ${_objects} INCLUDES ${_fuzz_includes}
            LIBS ${_fuzz_libs} FLAGS -fsanitize=fuzzer-no-link)
    target_link_options(${name} PRIVATE -fsanitize=fuzzer)
  else()
    ms_test(${name} SOURCES "${file}" "${_rt}/fuzz/driver.c" ${_fuzz_deps_${short}} OBJECTS ${_objects}
            INCLUDES ${_fuzz_includes} LIBS ${_fuzz_libs})
  endif()
  set_property(TEST ${name} PROPERTY DISABLED TRUE)
endforeach()
