# The native runtime in C

## Summary

- Problem: the Rust runtime (`ms-rt`, 42k lines, and the `ms-std-*` natives, 64k) costs more memory per parked task and per idle connection than wanted, reaches programs only as calls, and its layout (one crate per stdlib module, signatures scraped from Rust) has no layering reason.
- Change: a C runtime in `runtime/` with one ABI header, a layered layout, flat tables instead of heap nodes, and libuv, llhttp, nghttp2, OpenSSL and RE2 in place of the Rust crates that do those jobs today.
- Decision: direction set by Chinmay (below). This PR ships stage 0 only: the folder and the one build of the third-party libraries.

## Status

Approved direction, 2026-11-20, checked against `660429d4`. Chinmay: "lets revive the effort of rewriting the backend to c"; "for networking stack lets use nodejs libs libuv, nghttp, llhttp, with openssl"; "lets use re2 for regex"; no Rust left for regex, time zones or archives; "one single build for all dependencies and later we can cache it". Skeptical review (2026-11-20): build with changes; stage 0 may ship. Applied: stale inlining figures and the bitcode step removed, the frame breakdown marked as unverified, a park-path measurement added before stage 2 (the reviewer asked for a stop condition; Chinmay's direction is that the C port is not conditional), the libuv fit and platform items made stage 1 work instead of open questions.

## Problem

- Measured (wiki `task-stacks-are-512-kib-slots-in-256-mib-regions`, 2026-11-20): an idle websocket connection costs 7.1 KB after #4613. A parked websocket handler's stack packs to 3.5 KB; a bare parked task keeps 2.9 KB of frames from `Promise.wait` to `switch_away`. Unverified (reported by the websocket work, no committed breakdown): about 2.4 KB of the 3.5 KB is runtime frames.
- Verified (`crates/DESIGN.md` "Runtime fast paths"): the runtime reaches programs only as calls; a path that must inline is a MIR operation the compiler emits (`proposals/retire-ms-rt-hot.md`). That rule stays: this proposal adds no bitcode linking.
- Verified: native signatures are scraped from Rust into `crates/ms-lower/rt_symbols.txt` (`crates/xtask/src/main.rs` `symbols`). With no Rust to scrape, they need a new source.
- Hypothesis, to be measured per stage: the same design compiles to about the same machine code from Rust or C. What C gives on its own is hand-sized frames on the park path and no `Result` plumbing (release is already `panic = "abort"`). What it costs is Rust's checking in about 100k lines whose history is concurrency bugs. The large memory win is design: idle connections that hold no task.

## Design

```
runtime/
  include/ms_rt.h   layouts, status codes, signatures: the single source of truth
  sys/{linux,darwin,windows}/   memory regions, context switch, clocks, files
  core/             alloc, task, sched, fault, string, vec, map, promise, pipe
  io/               reactor on libuv; files, pipes, processes, terminal, sockets
  net/              http1 (llhttp), http2 (nghttp2), tls (OpenSSL), websocket, dns
  std/<module>.c    natives of one stdlib module
  third_party/      pins, vendored llhttp, one build script
  tests/            smoke programs, unit tests under sanitizers
```

- Layering `sys` < `core` < `io` < `net`, `std`; an include check enforces it. `core` never includes libuv.
- One build: `cargo xtask runtime` calls clang per target (llvm-mingw on Windows, which `ring` needs today) and writes `libms_rt.a`. No `cc` crate. `ms-rt-abi` is generated from `ms_rt.h`; a test compares the two.
- Signatures are written once in `ms_rt.h`; a generator reads the header for the lowering table and fails when a symbol named by `stdlib/*.ms` is missing from the archive or an exported one is unused.
- Tasks, promises and connections are rows in struct-of-arrays tables, addressed by a 32-bit index with generation and state in the upper bits.
- An idle connection is a table row and a `uv_tcp_t`; a task attaches only while a handler runs. How a handler waits is a language question with its own proposal.
- libcrypto replaces `ring`, `rustls`, the RustCrypto crates, `p256`, `p384`, `p521`, `rsa`, `ed25519-dalek` and `x25519-dalek`. RE2 replaces `regex`; it is C++17 and brings Abseil, so the archive links the C++ runtime statically.
- Third-party build: `runtime/third_party/build.sh [triple]` builds everything into `target/c-libs/<triple>-<key>/`; the key hashes the pins, the script, vendored sources, the triple and the compiler versions.
- The Rust runtime stays buildable and selected per symbol until the C runtime passes the conformance corpus on all six platforms; it is then deleted in one PR.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `runtime/third_party` (this PR) | pins, vendored llhttp, one build, smoke programs | `sh runtime/third_party/smoke.sh` |
| `crates/xtask` | builds the C archive per target | six-platform CI dispatch |
| `crates/ms-rt-abi`, `ms-lower` | layouts and symbol table generated from `ms_rt.h` and `stdlib/*.ms` | drift test in `make verify` |
| `ms-rt`, `ms-std-*` | replaced symbol by symbol, then removed | conformance corpus on both runtimes |
| `ms-repo-check licenses` | C library notices join the inventory | `make licenses-check` |

## Alternatives

- Do nothing: 7.1 KB per idle connection is under Node's 11 KB, and the task-free design could be built in Rust. Rejected by direction; it keeps the opaque runtime and the Rust frame sizes.
- Port only the park path: proves the frame saving cheaply but leaves two runtimes for good.
- Hand-written TLS, HTTP/2 and regex in C: months of security-critical work for no measured gain over the chosen libraries.
- BearSSL or mbedTLS, PCRE2: smaller, but not what Node ships, and PCRE2 backtracks.

## Stages

0. Folder, pins, one third-party build, smoke programs (this PR): smoke passes on Linux; macOS and Windows by CI dispatch.
1. `ms_rt.h`, the xtask build, generators, per-symbol selection: `make verify` unchanged, six platforms green. Settled here, with a written note each: static C++ runtime under the glibc 2.28 floor, libc++ for musl, OpenSSL's Configure under llvm-mingw on both Windows architectures, the system trust store, and size and start-up budgets for a program that uses no TLS or regex.
1a. Measurement, not a gate: port the park path (wait, switch, socket wait) and record stack bytes per parked task against the Rust runtime on the same design, so the gain from C is reported apart from the gain from design changes. The port continues either way (Chinmay, 2026-11-20: "moving to c is essential"; design changes come in addition).
2. `sys` and `core`: conformance on both runtimes; instructions per call against checked C.
3. `io` on libuv, then `net`, after a design note on the fit: one loop per scheduler thread, `uv_poll_t` or streams, how a handle moves between threads (`sched::Pin::touch` today), and how the asynchronous `uv_close` meets a guard jump. Tasks and http-tail benchmarks no slower; memory per idle connection against 7.1 KB, with TLS measured separately (an OpenSSL `SSL` with buffers can cost 20 to 40 KB).
4. `std/*`, RE2, time zones, archives; C unit tests under ASan and UBSan and fuzzing of the parsers in the nightly job, outside the PR budget; delete the Rust runtime.

The task-free connection design is measured on its own, in Rust or C, so its gain is not counted as C's.

## Open questions

- Compression: `flate2` and `miniz_oxide` need a C replacement; zlib would be a new dependency and needs approval. Recommendation: zlib.
- Time zones: bundled IANA data read by Manuscript code, not a C library. Recommendation: yes.
- `--static` (musl) builds need a C++ runtime for RE2. Recommendation: build libc++ for musl in the dependency build, or drop RE2's Abseil-heavy paths if measurement says it is cheap.
