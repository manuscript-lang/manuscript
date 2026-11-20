# runtime

The C runtime that compiled Manuscript programs link, replacing the Rust `ms-rt` and `ms-std-*` crates step by step. Plan and reasons: [proposals/c-runtime.md](../proposals/c-runtime.md). Only the third-party build exists so far.

```
runtime/
  include/       ms_rt.h, the ABI (to come)
  sys/           per-OS code: linux, darwin, windows (to come)
  core/          alloc, task, sched, fault, string, vec, map, promise, pipe (to come)
  io/            reactor on libuv (to come)
  net/           http1 (llhttp), http2 (nghttp2), tls (OpenSSL), websocket (to come)
  std/           natives per stdlib module (to come)
  third_party/   pinned dependencies and the one build for all of them
  tests/         smoke programs and, later, unit tests
```

Layering: `sys` < `core` < `io` < `net` and `std`. `core` never includes libuv.

## Third-party libraries

`sh runtime/third_party/build.sh [triple]` builds every dependency in one go into `target/c-libs/<triple>-<key>/{lib,include}`. `build.sh key [triple]` prints the key, a hash of the pins, the script, the vendored llhttp, the triple and the compiler versions: cache the folder on that key and any change rebuilds all of it. `sh runtime/third_party/smoke.sh` builds and runs the smoke programs in `runtime/tests`. Building needs a C and C++17 compiler, make, cmake and perl; using `ms` needs none of them.

| Library | Version | Use | License |
| --- | --- | --- | --- |
| libuv | 1.51.0 | event loop | MIT |
| llhttp | 9.2.1 (vendored) | HTTP/1 parsing | MIT |
| nghttp2 | 1.66.0 | HTTP/2 | MIT |
| OpenSSL | 3.5.4 | TLS and crypto | Apache-2.0 |
| RE2 | 20240702 | regex (linear time, no backreferences) | BSD-3-Clause |
| Abseil | 20240722.0 | RE2 dependency | Apache-2.0 |
| QBE | 1.3 (vendored, unmodified) | debug code generator, built to `bin/qbe` | MIT |

Versions and SHA-256 sums are in `third_party/c-libs.lock`. Chinmay approved libuv, nghttp2, llhttp, OpenSSL and RE2 on 2026-11-20; any other library needs his approval.
