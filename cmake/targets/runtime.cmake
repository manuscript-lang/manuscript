# One implementation per OS family; the posix files branch on __APPLE__ for macOS constants.
if(WIN32)
  set(MS_OS_DIR windows)
else()
  set(MS_OS_DIR posix)
endif()
file(GLOB ms_sys_os CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/runtime/sys/${MS_OS_DIR}/*.c")
ms_library(ms_sys runtime/sys
  SOURCES
    ${ms_sys_os} thread.c
  LINK ms_abi ms_base uv)

ms_library(ms_io runtime/io
  SOURCES
    ring.c edge.c reactor.c refused.c pool.c stdout.c stop.c ${MS_OS_DIR}/platform.c
  LINK ms_abi ms_base ms_sys uv)

ms_library(ms_core runtime/core
  SOURCES
    alloc.c stats.c context.c stack.c timers.c queue.c frames.c record.c isolate.c watch.c unwind.c fault.c sched.c
    segment.c park.c token.c task.c eq.c fault_kept.c fault_abi.c task_abi.c obj.c promise.c promise_end.c
    promise_wait.c promise_abi.c promise_remote.c group.c pipe.c cancel.c worker.c drop_queue.c release.c
  LINK ms_sys ms_base mimalloc)
# Tasks, promises and the queue call each other on every start and wait: they compile as one unit so those calls
# inline. The other core files stay separate, so a file-local name there never meets one here.
set(ms_core_hot queue.c sched.c token.c timers.c task.c task_abi.c promise.c promise_end.c promise_wait.c promise_abi.c
    promise_remote.c cancel.c worker.c isolate.c)
list(TRANSFORM ms_core_hot PREPEND "${CMAKE_SOURCE_DIR}/src/runtime/core/")
set_target_properties(ms_core PROPERTIES UNITY_BUILD ON UNITY_BUILD_MODE GROUP)
set_source_files_properties(${ms_core_hot} PROPERTIES UNITY_GROUP scheduling)

# Value natives of the runtime core: strings, bytes, lists, maps, numbers and text formatting.
ms_library(ms_values runtime/core
  SOURCES
    ascii_chars.c bits.c bytes.c bytes_text.c index_fault.c list.c list_derive.c list_edit.c list_fault.c
    list_range.c map.c map_build.c num.c num_sized.c num_text.c set.c slot.c sort.c sort_ints.c string_case.c
    string_cut.c string_lists.c string_join.c string_make.c string_normalize.c string_quote.c string_query.c
    string_split.c unicode_case_tables.c unicode_norm_index.c unicode_norm_leaf.c unicode_norm_pool.c
    unicode_norm_records.c
  LINK ms_base)

# The process entry: msrt_start, the arguments, the exit and stop hooks.
ms_library(ms_entry runtime/entry
  SOURCES
    args.c profile.c start.c stop_hooks.c test_support.c
  LINK ms_abi ms_base ms_sys ms_io ms_core uv)

ms_executable(profile_unit runtime/entry SOURCES profile_unit.c LINK ms_entry)
add_test(NAME entry_profile COMMAND profile_unit)

# Natives of the standard library modules, built on base and the vendored libraries.
ms_library(ms_std_text runtime/std
  SOURCES
    regex_abi.c regex_engine.c regex_replace.c regex_scan.c regex_screen.c regex_text.c shape_equal.c shape_text.c
    unicode.c unicode_width.c
  LINK ms_base ms_values pcre2)

# @std/data: json (scanner, document handle, tree builder, writer), checksum (zlib), encoding, html and archive.
ms_library(ms_std_data runtime/std
  SOURCES
    json_doc.c json_scalar.c json_scan.c json_tree.c json_write.c shape_json_write.c shape_json_read.c checksum.c
    encoding.c html.c html_entity.c archive.c archive_tar.c
    archive_zip.c
  LINK ms_base ms_values ms_std_text ms_std_compress zlib)

# @std/time: durations, instants, clocks, RFC 3339 text, calendar fields, the host zone setting and the zone database
# (tzdata.bin, built by tools/tzdata/pack.py).
set(tzdata_c ${MS_GEN}/tzdata.c)
add_custom_command(
  OUTPUT ${tzdata_c}
  COMMAND ${CMAKE_COMMAND} -DINPUT=${CMAKE_SOURCE_DIR}/src/runtime/std/tzdata.bin -DOUTPUT=${tzdata_c} -DSYMBOL=ms_tzdata
          -P ${CMAKE_SOURCE_DIR}/cmake/EmbedBlob.cmake
  DEPENDS ${CMAKE_SOURCE_DIR}/src/runtime/std/tzdata.bin ${CMAKE_SOURCE_DIR}/cmake/EmbedBlob.cmake
  COMMENT "Embedding tzdata.bin")
ms_library(ms_std_time runtime/std
  SOURCES
    time.c time_civil.c time_clock.c time_system.c time_text.c time_zone.c ${tzdata_c}
  LINK ms_base)

# @std/math: libm functions and the wide-word helpers.
ms_library(ms_std_math runtime/std
  SOURCES
    stdmath.c
  LINK ms_base m)

# @std/random: operating system entropy through libcrypto, and the version-7 UUID stamp sequence.
ms_library(ms_std_random runtime/std
  SOURCES
    random.c
  LINK ms_base openssl_crypto)

# @std/io/archive compression: gzip, zlib and raw deflate on zlib, whole-buffer and streaming.
ms_library(ms_std_compress runtime/std
  SOURCES
    compress.c
  LINK ms_base ms_values zlib)

# @std/crypto: digests, HMAC, key derivation, AES, Ed25519, ECDSA, ECDH and RSA on libcrypto.
ms_library(ms_std_crypto runtime/std
  SOURCES
    crypto.c crypto_asym.c
  LINK ms_base ms_values openssl_crypto)

# @std/os/path: glob compilation and matching, with brace expansion.
ms_library(ms_std_path runtime/std
  SOURCES
    path_brace.c path_glob.c path_syntax.c
  LINK ms_base)

# @std/math BigInt and Decimal: arbitrary-precision integers on libcrypto's BIGNUM, with an NTT multiply for wide products.
ms_library(ms_std_bignum runtime/std
  SOURCES
    bignum.c bignum_ntt.c bignum_text.c bigint.c decimal.c decimal_text.c
  LINK ms_base ms_values ms_std_text openssl_crypto m)

# @std/os/system and the process environment: host names, users, CPUs, memory, priorities and network interfaces, one libuv call each (no event loop).
ms_library(ms_std_system runtime/std
  SOURCES
    system.c process_env.c
  LINK ms_base ms_values uv)

# @std/process natives that need the scheduler or the OS beyond libuv: ids, groups, title, usage, signal watchers.
ms_library(ms_std_process runtime/std
  SOURCES
    fail.c process.c process_memory.c signals.c command.c child.c run.c spawn.c
  LINK ms_base ms_values ms_sys ms_io ms_core ms_entry ms_std_fs uv)

# @std/net sockets on libuv: one loop thread, connections, listeners, datagrams, the Network handle.
ms_library(ms_std_sockets runtime/std
  SOURCES
    net_loop.c net_core.c net_conn.c net_listen.c net_dgram.c net_filter.c net_dns.c net_dns_client.c net_network.c
    net_tls.c net_tls_conn.c
  LINK ms_base ms_values ms_sys ms_io ms_core uv ms_std_process ms_std_net openssl_ssl)
if(WIN32)
  target_link_libraries(ms_std_sockets PUBLIC iphlpapi) # GetNetworkParams: the host's DNS servers
endif()

# The WebSocket natives, over the connections of ms_std_sockets.
ms_library(ms_std_ws runtime/std
  SOURCES
    ws_abi.c ws_dial.c http_network.c http_serve_conn.c http_serve_steal.c http_serve_exchange.c http_serve_h2.c
    http_serve_h2_exchange.c http_serve_abi.c
  LINK ms_base ms_values ms_core ms_std_net ms_std_sockets)

# @std/fs natives that work on paths: whole files, metadata, listing, directories, removal, links, attributes.
ms_library(ms_std_fs runtime/std
  SOURCES
    fs_job.c fs_read.c fs_stat.c fs_ops.c fs_dir.c stream.c file.c fs_tree.c fs_copy.c fs_glob.c fs_watch.c io.c
    streams.c terminal.c terminal_read.c
  LINK ms_base ms_sys ms_io ms_core uv ms_std_process)

# @std/net: IP addresses, CIDR ranges, host:port text and the network diagnostics (no event loop).
ms_library(ms_std_net runtime/std
  SOURCES
    http_abi.c http_h1.c http_h1_body.c http_h1_framing.c http_h1_write.c h2.c h2_send.c http_client.c
    http_client_abi.c http_client_send.c http_engine.c http_exchange.c http_redirect.c http_url.c http_headers.c
    http_sniff.c http_sync.c http_target.c net.c net_addr.c net_ip.c ws_decode.c ws_frame.c ws_handshake.c
    ws_session.c ws_receive.c tls_cert.c tls_dn.c tls_pem.c
  LINK ms_base ms_values ms_std_time ms_std_random ms_std_data ms_std_crypto ms_std_compress ms_sys uv llhttp curl nghttp2 zlib openssl_crypto)

# The libcrypto users compile against OpenSSL's generated headers, so they wait for its build.
foreach(target ms_std_random ms_std_crypto ms_std_bignum ms_std_net)
  add_dependencies(${target} openssl_build)
endforeach()

# Unit tests of pure data structures only; the corpus is the gate.
ms_executable(core_alloc_unit runtime/core SOURCES alloc_unit.c LINK ms_core)
add_test(NAME core_alloc COMMAND core_alloc_unit)
ms_executable(core_unit runtime/core SOURCES core_unit.c LINK ms_core)
add_test(NAME core_unit COMMAND core_unit)

# ld64 resolves archive members in any order, and CMake has no RESCAN link group for it.
if(APPLE)
  set(shape_libs ms_std_text ms_std_data ms_std_bignum ms_std_compress zlib ms_values ms_core ms_sys)
else()
  set(shape_libs "$<LINK_GROUP:RESCAN,ms_std_text,ms_std_data,ms_std_bignum,ms_std_compress,zlib,ms_values,ms_core,ms_sys>")
endif()
ms_executable(shape_unit runtime/std SOURCES shape_unit.c LINK ${shape_libs} m)
add_test(NAME std_shape COMMAND shape_unit)

# The public suffix list is in the binary and libcurl uses it (cookies for `co.uk` are refused).
ms_executable(http_psl_unit runtime/std SOURCES http_psl_unit.c LINK curl psl_static zlib nghttp2 openssl_ssl openssl_crypto)
add_test(NAME std_psl COMMAND http_psl_unit)

# Everything a program links, in one name.
add_library(ms_runtime INTERFACE)
target_link_libraries(ms_runtime INTERFACE ms_abi ms_sys ms_io ms_core ms_entry ms_values ms_std_text ms_std_data
  ms_std_time ms_std_math ms_std_random ms_std_compress ms_std_crypto ms_std_path ms_std_bignum ms_std_system
  ms_std_net ms_std_sockets ms_std_ws ms_std_process ms_std_fs)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND MS_LIBC STREQUAL "glibc")
  # The process entry, the stat family and aarch64 pthread_atfork that glibc 2.28 lacks; for program links, never for ms itself.
  set(glibc_compat sys/glibc_stat.c sys/glibc_start.c)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    list(APPEND glibc_compat sys/glibc_atfork.c)
  endif()
  ms_library(ms_glibc_compat runtime SOURCES ${glibc_compat})
  target_link_libraries(ms_runtime INTERFACE ms_glibc_compat)
endif()
