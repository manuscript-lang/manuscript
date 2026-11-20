[Wiki](../index.md) › [Runtime](index.md)

# A runtime symbol moves to C by listing it in `runtime/c-symbols.txt`

Verified (2026-11-20, Linux x86-64): `cargo xtask runtime` compiles `runtime/{sys,core,io,net,std}/**/*.c` with clang per target (musl gets `--target`; `third_party` and `tests` are skipped) and adds the objects to every archive with `ar`. `ms-rt/build.rs` reads `runtime/c-symbols.txt` only when xtask sets `MS_C_RUNTIME`, and emits `cfg(ms_c = "<symbol>")`; the Rust definition carries `#[cfg(not(ms_c = "<symbol>"))]`, so the archive has one definition and `cargo test` and clippy keep the Rust one. To port a symbol: write it in C, declare it in `runtime/include/ms_rt.h`, list it, gate the Rust fn, and run `cargo xtask symbols --check`, which fails when the header and the recorded signature disagree or a header function is unlisted. C unit tests live in `runtime/tests/core_*.c` and run under ASan and UBSan with `make c-test` (nightly, not the PR gate).

Rules: C under `core` and `sys` includes only freestanding headers (`stdint.h`, `stddef.h`, `stdbool.h`) so one source builds for glibc, musl and mingw; a symbol whose state is shared with Rust (the allocator, a table both sides touch) moves together with every Rust reader of that state, never alone, because Rust code inside `ms-rt` calls its own copy directly and would bypass the C one.

Apply when: porting any runtime symbol to C or changing the C build. Evidence: `crates/xtask/src/main.rs` (`add_c_runtime`, `check_c_abi`), `crates/ms-rt/build.rs`, [proposals/c-runtime.md](../../proposals/c-runtime.md). Verify: `cargo xtask symbols --check`, `make c-test`, the conformance corpus on the built archive.
