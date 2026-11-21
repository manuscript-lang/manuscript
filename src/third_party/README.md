# src/third_party

Vendored C libraries, pinned in `c-libs.lock` (version, tag, commit, SHA-256 of the vendored tree).

| Library | Version | Use |
| --- | --- | --- |
| mimalloc | 3.6.1 | Runtime allocator, bound through `ms_alloc_install` in `runtime/core/alloc.c`. CMake target `mimalloc`. |
| llhttp | 9.4.3 | HTTP parser for the net layer. CMake target `llhttp`. |
| PCRE2 | 10.49 | Regex engine for the std regex and unicode natives: 8-bit, Unicode properties, no JIT. CMake target `pcre2`; the generic headers are copied at configure time. |
| zlib | 1.4 | Compression for the std and net layers. CMake target `zlib` (`cmake/zlib.cmake`). |
| libuv | 1.53.0 | Event loop, one per thread, for the io and net layers. CMake target `uv`, static. |
| nghttp2 | 1.71.0 | HTTP/2 framing for the net layer. CMake target `nghttp2`, static, library only. |
| curl | 8.23.0 | Client library for the net layer (`lib` and `include`). CMake target `curl`, static, libcurl only: HTTP and HTTP/2, zlib, threaded resolver, TLS through OpenSSL on Unix. |
| OpenSSL | 3.5.4 | TLS and crypto for the net layer. The whole source minus `test` and `demos`; the build uses its own Configure (perl). CMake targets `openssl_ssl` and `openssl_crypto` (`cmake/openssl.cmake`, built out of tree). |

Check offline: `cmake -DSOURCE_DIR=. -P cmake/FetchCLibs.cmake` (also the `third_party_lock` ctest).
Update a pin: edit the tag and commit in the lock, run with `-DMODE=fetch`, then put the printed digest in the lock.
`ms_lint` skips this directory; do not edit vendored files by hand.
