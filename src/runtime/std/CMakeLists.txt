# Natives of the standard library modules, built on base and the vendored libraries.
add_library(ms_std_text STATIC
  regex_abi.c
  regex_engine.c
  regex_replace.c
  regex_scan.c
  regex_screen.c
  regex_text.c
  unicode.c
  unicode_width.c)
ms_target_defaults(ms_std_text)
target_link_libraries(ms_std_text PUBLIC ms_base ms_values pcre2)

# @std/data: json (scanner, document handle, tree builder, writer), checksum (zlib), encoding, html, url and archive.
add_library(ms_std_data STATIC
  json_doc.c
  json_scalar.c
  json_scan.c
  json_tree.c
  json_write.c
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
target_link_libraries(ms_std_data PUBLIC ms_base ms_values ms_std_compress zlib)

# @std/time: durations, instants, clocks, RFC 3339 text, calendar fields and the host zone setting.
add_library(ms_std_time STATIC
  time.c
  time_civil.c
  time_clock.c
  time_system.c
  time_text.c)
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
add_library(ms_std_process STATIC fail.c process.c signals.c)
ms_target_defaults(ms_std_process)
target_link_libraries(ms_std_process PUBLIC ms_base ms_values ms_sys ms_io ms_core ms_entry uv)

# @std/fs natives that work on paths: whole files, metadata, listing, directories, removal, links, attributes.
add_library(ms_std_fs STATIC fs_job.c fs_name.c fs_read.c fs_stat.c fs_ops.c)
ms_target_defaults(ms_std_fs)
target_link_libraries(ms_std_fs PUBLIC ms_base ms_sys ms_io ms_core uv ms_std_process)

# @std/net: IP addresses, CIDR ranges, host:port text and the network diagnostics (no event loop).
add_library(ms_std_net STATIC http_abi.c http_h1.c http_h1_body.c http_h1_framing.c http_h1_write.c http_headers.c http_sniff.c http_target.c net.c net_addr.c net_ip.c)
ms_target_defaults(ms_std_net)
target_link_libraries(ms_std_net PUBLIC ms_base ms_values ms_std_time llhttp)
