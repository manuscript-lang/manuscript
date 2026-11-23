# src/third_party

Vendored C libraries, pinned in `c-libs.lock` (version, tarball URL and checksum or tag and commit, SHA-256 of the vendored tree).

| Library | Version | Use |
| --- | --- | --- |
| mimalloc | 3.6.1 | Runtime allocator, bound through `ms_alloc_install` in `runtime/core/alloc.c`. Built with its own CMakeLists.txt (`add_subdirectory`, static, no override); CMake target `mimalloc` (alias of `mimalloc-static`). |
| llhttp | 9.4.3 | HTTP parser for the net layer. Built by its own CMakeLists.txt (static only); CMake target `llhttp` aliases `llhttp_static`. |
| PCRE2 | 10.49 | Regex engine for the std regex and unicode natives: 8-bit, Unicode properties, no JIT. Built by its own CMakeLists.txt; CMake target `pcre2` aliases `pcre2-8-static`. |
| zlib | 1.4 | Compression for the std and net layers. Built with its own `CMakeLists.txt`; target `zlib`. |
| libuv | 1.53.0 | Event loop, one per thread, for the io and net layers. Built by its own CMakeLists.txt (static only); CMake target `uv` aliases `uv_a`. |
| nghttp2 | 1.71.0 | HTTP/2 framing for the net layer. Built with its own `CMakeLists.txt` (`ENABLE_LIB_ONLY`, static); target `nghttp2`. The tree carries the `.in` files and stub `CMakeLists.txt` its top-level configure reads. |
| curl | 8.23.0 | Client library for the net layer. Built with its own `CMakeLists.txt` as an ExternalProject after OpenSSL (its configure step links against it); static libcurl only: HTTP and HTTP/2, zlib, threaded resolver, TLS through OpenSSL. CMake target `curl` (`cmake/curl.cmake`). |
| OpenSSL | 3.5.4 | TLS and crypto for the net layer. The whole source minus `test` and `demos`; the build uses its own Configure (perl). CMake targets `openssl_ssl` and `openssl_crypto` (`cmake/openssl.cmake`, built out of tree). |

Check offline: `cmake -DSOURCE_DIR=. -P cmake/FetchCLibs.cmake` (also the `third_party_lock` ctest).
Update a pin: edit the version, tarball URL and tarball sha256 in the lock (or the tag and commit for a tag clone), run with `-DMODE=fetch`, then put the printed digest in the lock. Libraries come from the upstream release tarball when there is one; mimalloc and llhttp, which publish none, come from a tag clone.
`ms_lint` skips this directory; do not edit vendored files by hand.
