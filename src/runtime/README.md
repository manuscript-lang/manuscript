# runtime

The C runtime that compiled Manuscript programs link, replacing the Rust `ms-rt` and `ms-std-*` crates step by step. Plan and reasons: [proposals/c-runtime.md](../../proposals/c-runtime.md). The third-party build and the C build (`src/runtime/core/num.c`, the allocator `alloc.c` and regions `region.c` so far) exist; `src/runtime/symbols/<module>.txt` lists the symbols defined in C, and [the wiki page](../../wiki/runtime/a-runtime-symbol-moves-to-c-by-listing-it-in-c-symbols.md) says how a symbol moves.

```
src/runtime/
  include/       ms_rt/base.h and one ms_rt/<module>.h per module: the ABI; ms_rt/sys.h, the OS layer
  sys/           the one door to the OS: posix (Linux, macOS) and windows for memory regions, the clock, descriptors, stack-overflow reporting and yielding; `thread.c` runs threads and sleep on libuv for every platform; sockets (net.h; Linux and macOS share posix_net.h, Windows has its own); glibc compat
  core/          alloc, task, sched, fault, string, vec, map, promise, pipe (num.c, desc.c, list.c, sort.c, bytes.c, map.c and map_api.c so far)
  io/            reactor on libuv (to come)
  net/           http1 (llhttp), tls (OpenSSL), ws frames, h2 (nghttp2) and the connection rows done as tested units; wiring to come
  std/           natives per stdlib module (path so far; crypto and regex wait on the C libraries)
  third_party/   pinned dependencies and the one build for all of them
  tests/         smoke programs and unit tests (`make c-test`, under ASan and UBSan)
  fuzz/          fuzz harnesses and seed corpus (`make c-fuzz`); nightly
```

Layering: `sys` < `core` < `io` < `net` and `std`. `core` never includes libuv; it reaches threads through `ms_rt/sys.h`.

## Third-party libraries

Runtime archives link our own builds of vendored sources (Chinmay, 2026-11-20: vendored and built in the repo, no prebuilt downloads). System packages remain for plain CMake dev builds (`MS_C_LIBS=system`).

- `sh src/runtime/third_party/libs.sh install` installs CMake, Ninja, ccache, pkg-config, libuv, nghttp2, OpenSSL, PCRE2 and zlib with apt, Homebrew, apk or vcpkg.
- One CMake project builds every C part: `CMakeLists.txt` and `cmake/` (`MsLibs` finds the libraries, `MsRuntime` selects the sources and folds the libraries into the archive objects, `MsTests` defines the tests and fuzz harnesses). Sources are found by glob, so a new `.c` file under `src/runtime/` needs no edit there. `cmake -S . -B target/cmake/host -G Ninja && cmake --build target/cmake/host && ctest --test-dir target/cmake/host`, or `make c-configure c-build c-test`. ccache is the compiler launcher whenever it is installed (`-DMS_CCACHE=OFF` opts out).
- Libraries: `MS_C_LIBS=system` (default) finds them with pkg-config; `MS_C_LIBS=prefix` takes `MS_LIBS_PREFIX/{include,lib}`. Every runtime archive (glibc, musl, macOS, Windows) uses the sources vendored under `src/runtime/third_party/{libuv,nghttp2,openssl,pcre2,zlib,curl}` (trimmed of tests and docs; `c-libs.lock` records the upstream version, URL and SHA-256 of each), which `build.sh <triple>` builds into `target/c-libs/<triple>-pinned-<key>/{lib,include}` (needs make, cmake and perl; `build.sh key <triple>` prints the cache key). libcurl is HTTP and HTTPS only, on our OpenSSL, nghttp2 and zlib. To bump a library, replace its folder with the new release (delete tests and docs) and update its row in `c-libs.lock`. llhttp is vendored and compiled by CMake.
- `cmake -P cmake/BuildRuntime.cmake` calls CMake and folds the objects, and the members of every library the C sources include, into each runtime archive (Linux glibc and musl so far), so programs link nothing extra and carry only the members they reach. `src/runtime/sys/glibc/compat.c` covers the few glibc functions newer than 2.28 that the system libraries call.
- Oldest versions the C runtime may assume, from Ubuntu 24.04: libuv 1.48, nghttp2 1.59, OpenSSL 3.0, PCRE2 10.42, zlib 1.3. Code that needs something newer checks for it at build time. The smoke programs (`clibs_smoke*`, `tls_test`, `ws_test`, `conn_test`, `h2_test`) run under `make c-test`.
- Not proven yet: the macOS and Windows builds of `build.sh` (written, not run), and Homebrew, apk and vcpkg installs (only apt has been run).

| Library | Version | Use | License |
| --- | --- | --- | --- |
| libuv | 1.51.0 | event loop | MIT |
| llhttp | 9.2.1 (vendored) | HTTP/1 parsing | MIT |
| nghttp2 | 1.66.0 | HTTP/2 | MIT |
| OpenSSL | 3.5.4 | TLS and crypto | Apache-2.0 |
| zlib | 1.3.2 | deflate and inflate | Zlib |
| PCRE2 | 10.47 | regex (8-bit library, JIT; a match limit bounds backtracking) | BSD-3-Clause |

Versions and SHA-256 sums are in `third_party/c-libs.lock`. Chinmay approved libuv, nghttp2, llhttp, OpenSSL, PCRE2 and zlib on 2026-11-20 (PCRE2 replaced RE2 the same day, to keep C++ out of programs); any other library needs his approval.

## Style and safety

Every C file follows [C style and safety](../../documentation/contributing/c-style.md). `make c-lint` checks it; `ms_rt/safe.h` holds the checked sizes, spans and attribute macros.
