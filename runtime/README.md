# runtime

The C runtime that compiled Manuscript programs link, replacing the Rust `ms-rt` and `ms-std-*` crates step by step. Plan and reasons: [proposals/c-runtime.md](../proposals/c-runtime.md). The third-party build and the C build (`runtime/core/num.c`, the allocator `alloc.c` and regions `region.c` so far) exist; `runtime/symbols/<module>.txt` lists the symbols defined in C, and [the wiki page](../wiki/runtime/a-runtime-symbol-moves-to-c-by-listing-it-in-c-symbols.md) says how a symbol moves.

```
runtime/
  include/       ms_rt/base.h and one ms_rt/<module>.h per module: the ABI; ms_rt/sys.h, the OS layer
  sys/           the one door to the OS: posix (Linux, macOS) and windows for memory regions, the clock, threads and sleep; sockets (net.h; Linux and macOS share posix_net.h, Windows has its own); glibc compat
  core/          alloc, task, sched, fault, string, vec, map, promise, pipe (num.c, desc.c, list.c, sort.c, bytes.c, map.c and map_api.c so far)
  io/            reactor on libuv (to come)
  net/           http1 (llhttp), tls (OpenSSL), ws frames, h2 (nghttp2) and the connection rows done as tested units; wiring to come
  std/           natives per stdlib module (to come)
  third_party/   pinned dependencies and the one build for all of them
  tests/         smoke programs and unit tests (`make c-test`, under ASan and UBSan)
  fuzz/          fuzz harnesses and seed corpus (`make c-fuzz`); nightly
```

Layering: `sys` < `core` < `io` < `net` and `std`. `core` never includes libuv.

## Third-party libraries

Libraries come from the system packages first (Chinmay, 2026-11-20); our own pinned builds are for release archives and come later on every platform.

- `sh runtime/third_party/libs.sh install` installs libuv, nghttp2, OpenSSL, PCRE2 and zlib with apt, Homebrew, apk or vcpkg.
- `libs.sh cflags` and `libs.sh libs <name>...` (names: `uv llhttp nghttp2 ssl crypto pcre2 z`) print the compiler and linker flags; every script and test gets its flags there and names no library path itself. llhttp and QBE are vendored and built in both modes; `libs.sh dir` prints their folder.
- `MS_C_LIBS=pinned` switches to the versions in `c-libs.lock`, built by `build.sh [triple]` into `target/c-libs/<triple>-pinned-<key>/{lib,include}` (needs make, cmake and perl). `build.sh key [triple]` prints the cache key.
- `libs.sh archives <name>...` prints each library's static archive. `cargo xtask runtime` folds the archives of the libraries the C sources include into every runtime archive it can (Linux glibc and musl so far; musl takes pinned builds made with `musl-gcc`), so programs link nothing extra and carry only the members they reach. `runtime/sys/glibc/compat.c` covers the few glibc functions newer than 2.28 that the system libraries call.
- Oldest versions the C runtime may assume, from Ubuntu 24.04: libuv 1.48, nghttp2 1.59, OpenSSL 3.0, PCRE2 10.42, zlib 1.3. Code that needs something newer checks for it at build time. `sh runtime/third_party/smoke.sh` runs the smoke programs in either mode.
- Not proven yet: Homebrew, apk and vcpkg installs (only apt has been run), and Windows, where vcpkg builds from source.

| Library | Version | Use | License |
| --- | --- | --- | --- |
| libuv | 1.51.0 | event loop | MIT |
| llhttp | 9.2.1 (vendored) | HTTP/1 parsing | MIT |
| nghttp2 | 1.66.0 | HTTP/2 | MIT |
| OpenSSL | 3.5.4 | TLS and crypto | Apache-2.0 |
| zlib | 1.3.2 | deflate and inflate | Zlib |
| PCRE2 | 10.47 | regex (8-bit library, JIT; a match limit bounds backtracking) | BSD-3-Clause |
| QBE | 1.3 (vendored, unmodified) | debug code generator, built to `bin/qbe` | MIT |

Versions and SHA-256 sums are in `third_party/c-libs.lock`. Chinmay approved libuv, nghttp2, llhttp, OpenSSL, QBE, PCRE2 and zlib on 2026-11-20 (PCRE2 replaced RE2 the same day, to keep C++ out of programs); any other library needs his approval.

## Style and safety

Every C file follows [C style and safety](../documentation/contributing/c-style.md). `make c-lint` checks it; `ms_rt/safe.h` holds the checked sizes, spans and attribute macros.
