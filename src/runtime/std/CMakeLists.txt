# Natives of the standard library modules, built on base and the vendored libraries.
add_library(ms_std_text STATIC
  regex_abi.c
  regex_engine.c
  regex_replace.c
  regex_scan.c
  regex_screen.c
  regex_text.c
  shape_text.c
  unicode.c
  unicode_width.c)
ms_target_defaults(ms_std_text)
target_link_libraries(ms_std_text PUBLIC ms_base ms_values pcre2)

add_executable(shape_unit shape_unit.c)
ms_target_defaults(shape_unit)
target_link_libraries(shape_unit PRIVATE "$<LINK_GROUP:RESCAN,ms_std_text,ms_std_data,ms_std_compress,zlib,ms_values,ms_core,ms_sys>" m)
add_test(NAME std_shape COMMAND shape_unit)

# @std/data: json (scanner, document handle, tree builder, writer), checksum (zlib), encoding, html, url and archive.
add_library(ms_std_data STATIC
  json_doc.c
  json_scalar.c
  json_scan.c
  json_tree.c
  json_write.c
  shape_json_write.c
  checksum.c
  encoding.c
  html.c
  html_entity.c
  url.c
  url_escape.c
  url_parse.c
  url_render.c
  archive.c
  archive_tar.c
  archive_zip.c)
ms_target_defaults(ms_std_data)
target_link_libraries(ms_std_data PUBLIC ms_base ms_values ms_std_text ms_std_compress zlib)

# @std/time: durations, instants, clocks, RFC 3339 text, calendar fields, the host zone setting and the zone database
# (tzdata.bin, built by tools/tzdata/pack.py).
set(tzdata_c ${CMAKE_CURRENT_BINARY_DIR}/tzdata.c)
add_custom_command(
  OUTPUT ${tzdata_c}
  COMMAND ${CMAKE_COMMAND} -DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/tzdata.bin -DOUTPUT=${tzdata_c} -DSYMBOL=ms_tzdata
          -P ${PROJECT_SOURCE_DIR}/cmake/EmbedBlob.cmake
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/tzdata.bin ${PROJECT_SOURCE_DIR}/cmake/EmbedBlob.cmake
  COMMENT "Embedding tzdata.bin")
add_library(ms_std_time STATIC
  time.c
  time_civil.c
  time_clock.c
  time_system.c
  time_text.c
  time_zone.c
  ${tzdata_c})
ms_target_defaults(ms_std_time)
target_link_libraries(ms_std_time PUBLIC ms_base)

# @std/math: libm functions and the wide-word helpers.
add_library(ms_std_math STATIC stdmath.c)
ms_target_defaults(ms_std_math)
target_link_libraries(ms_std_math PUBLIC ms_base m)

# @std/random: operating system entropy through libcrypto, and the version-7 UUID stamp sequence.
add_library(ms_std_random STATIC random.c)
ms_target_defaults(ms_std_random)
add_dependencies(ms_std_random openssl_build)
target_link_libraries(ms_std_random PUBLIC ms_base openssl_crypto)

# @std/io/archive compression: gzip, zlib and raw deflate on zlib, whole-buffer and streaming.
add_library(ms_std_compress STATIC compress.c)
ms_target_defaults(ms_std_compress)
target_link_libraries(ms_std_compress PUBLIC ms_base ms_values zlib)

# @std/crypto: digests, HMAC, key derivation, AES, Ed25519, ECDSA, ECDH and RSA on libcrypto.
add_library(ms_std_crypto STATIC crypto.c crypto_asym.c)
ms_target_defaults(ms_std_crypto)
add_dependencies(ms_std_crypto openssl_build)
target_link_libraries(ms_std_crypto PUBLIC ms_base ms_values openssl_crypto)

# @std/os/path: glob compilation and matching, with brace expansion.
add_library(ms_std_path STATIC path_brace.c path_glob.c path_syntax.c)
ms_target_defaults(ms_std_path)
target_link_libraries(ms_std_path PUBLIC ms_base)

# @std/math BigInt and Decimal: arbitrary-precision integers on libcrypto's BIGNUM, with an NTT multiply for wide products.
add_library(ms_std_bignum STATIC
  bignum.c
  bignum_ntt.c
  bignum_text.c
  bigint.c
  decimal.c
  decimal_text.c)
ms_target_defaults(ms_std_bignum)
add_dependencies(ms_std_bignum openssl_build)
target_link_libraries(ms_std_bignum PUBLIC ms_base ms_values openssl_crypto m)

# @std/os/system and the process environment: host names, users, CPUs, memory, priorities and network interfaces, one libuv call each (no event loop).
add_library(ms_std_system STATIC system.c process_env.c)
ms_target_defaults(ms_std_system)
target_link_libraries(ms_std_system PUBLIC ms_base ms_values uv)

# @std/process natives that need the scheduler or the OS beyond libuv: ids, groups, umask, title, usage, signal watchers.
add_library(ms_std_process STATIC fail.c process.c signals.c command.c child.c run.c spawn.c)
ms_target_defaults(ms_std_process)
target_link_libraries(ms_std_process PUBLIC ms_base ms_values ms_sys ms_io ms_core ms_entry ms_std_fs uv)

# @std/net sockets on libuv: one loop thread, connections, listeners, datagrams, the Network handle.
add_library(ms_std_sockets STATIC net_loop.c net_core.c net_conn.c net_listen.c net_dgram.c net_filter.c net_dns.c net_dns_client.c net_network.c net_tls.c net_tls_conn.c)
ms_target_defaults(ms_std_sockets)
target_link_libraries(ms_std_sockets PUBLIC ms_base ms_values ms_sys ms_io ms_core uv ms_std_process ms_std_net openssl_ssl)
if(WIN32)
  target_link_libraries(ms_std_sockets PUBLIC iphlpapi) # GetNetworkParams: the host's DNS servers
endif()

# The WebSocket natives, over the connections of ms_std_sockets.
add_library(ms_std_ws STATIC ws_abi.c ws_dial.c http_network.c http_serve_conn.c http_serve_exchange.c http_serve_h2.c http_serve_h2_exchange.c http_serve_abi.c)
ms_target_defaults(ms_std_ws)
target_link_libraries(ms_std_ws PUBLIC ms_base ms_values ms_core ms_std_net ms_std_sockets)

# @std/fs natives that work on paths: whole files, metadata, listing, directories, removal, links, attributes.
add_library(ms_std_fs STATIC fs_job.c fs_name.c fs_read.c fs_stat.c fs_ops.c fs_dir.c stream.c file.c fs_tree.c fs_copy.c fs_glob.c fs_watch.c io.c streams.c terminal.c terminal_read.c)
ms_target_defaults(ms_std_fs)
target_link_libraries(ms_std_fs PUBLIC ms_base ms_sys ms_io ms_core uv ms_std_process)

# @std/net: IP addresses, CIDR ranges, host:port text and the network diagnostics (no event loop).
add_library(ms_std_net STATIC http_abi.c http_h1.c http_h1_body.c http_h1_framing.c http_h1_write.c h2.c h2_send.c http_client.c http_client_abi.c http_client_send.c http_engine.c http_exchange.c http_redirect.c http_url.c http_headers.c http_sniff.c http_sync.c http_target.c net.c net_addr.c net_ip.c ws_decode.c ws_frame.c ws_handshake.c ws_session.c ws_receive.c tls_cert.c tls_dn.c tls_pem.c)
ms_target_defaults(ms_std_net)
target_link_libraries(ms_std_net PUBLIC ms_base ms_values ms_std_time ms_std_random ms_std_data ms_std_crypto ms_std_compress ms_sys uv llhttp curl nghttp2 zlib openssl_crypto)
add_dependencies(ms_std_net openssl_build)
