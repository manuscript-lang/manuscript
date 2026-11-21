# Move the link driver out of ms-clif

## Summary

- Problem: `ms-clif` is the Cranelift backend and is going away with it, but it also owns everything that links a program (bundled lld, glibc and macOS stubs, the lld and LLVM-tools fetch, `BuildOptions`, `CopyProbe`, `Error`). The LLVM and C backends reach the linker through `ms_clif::link`, so deleting Cranelift means deleting the linker first.
- Change: move the link driver, its `build.rs` embedding, `BuildOptions`, `CopyProbe` and a link `Error` into `ms-build`; `ms-clif` keeps only code generation and gets its three knobs as plain `Options` fields. Behavior is unchanged.
- Decision requested: none (no language or user-visible change). This is stage 1 of removing the Rust link driver; stage 2 (port to C or Manuscript) is a later proposal.

## Status

Proposal, 2026-11-21, checked against `1f9fbbe24`. Direction (coordinator, from Chinmay's standing goals): move completely to C, no new dependencies, `crates/ms-clif/src/dwarf.rs` is out of scope here.

## Problem

Verified (`grep ms_clif:: crates`): outside `ms-clif`, `ms-build` (`native.rs`, `llvm.rs`, `llvm/obj.rs`, `llvm/tables.rs`, `lib.rs`, `examples/perf_stages.rs`) and `ms-cli` tests use only `link::{link_with, link_all, llvm_tools, debug_companion_path, is_static}`, `BuildOptions`, `CopyProbe` and `Error`. None of them is Cranelift.

- `crates/ms-clif/src/link*` is 1355 lines (plus 316 of tests) and `build.rs` 286; `cg.rs` and `lower.rs:202` read `BuildOptions` only for `clif_verify`, `poison_slots` and `dump_clif`.
- `ms-clif` pulls `sha2`, `rustls`, `rustls-native-certs`, `httparse`, `flate2` and `object` for the link driver alone; the Cranelift crates need none of them.
- The C backend (`MS_BACKEND=c`) already links through `ms_clif::link`, so the dependency points at a crate that should die.

## Design

- `ms-build` gains `link` (the files of `ms-clif/src/link`, `link.rs`, `options.rs`), a `build.rs` (the lld, mingw and musl embedding of `ms-clif/build.rs`, minus nothing else) and a link `Error(String)` with `From<ms_clif::Error>`. Paths are unchanged (`toolchain/lld.lock`, `OUT_DIR/linker`).
- `ms-clif::Options` drops `build: BuildOptions` and gains `clif_verify: bool` (default `cfg!(debug_assertions)`), `poison_slots: bool`, (`dump_clif` exists; the `build.dump_clif` OR in `cg.rs` goes). `ms-build/native.rs` fills them from its `BuildOptions`. `ms-clif` keeps its own `Error`.
- `ms-clif` re-exports nothing from the link driver: the cycle (`ms-clif` dev-depends on `ms-build`) forbids it, and every caller is updated in the same PR.
- Dependencies move with the code; `Cargo.lock` gains no package.
- Tests move with the code: `link/lld/tests.rs`, stub tests and `link_all` users in `ms-clif/tests` import `ms_build`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-build` | gains `link`, `options`, `build.rs`, deps | its unit tests, `tests/debug_artifacts.rs` |
| `crates/ms-clif` | loses `link*`, `options.rs`, `build.rs`, five deps; `Options` gets two fields | `tests/native.rs`, `tests/dwarf.rs` via `ms_build` |
| `crates/ms-cli` | imports from `ms_build` | `tests/build_backend.rs`, `tests/llvm.rs` |
| `ms-clif/examples/mirc.rs`, `tests/support/mod.rs` (shared with `ms-build/tests`) | import `ms_build` | both test crates |
| `Cargo.toml` dev-profile overrides, wiki links (about 6 pages), `tools/repo-check/checks_text.ms` layers, `timed-waits-allowed.txt`, `rust-scope/action.yml`, `rust-toolchain.toml` comment | path updates | `cargo metadata`, `make repo-check` |

Unchanged: `dwarf.rs` (the C LLVM emitter still needs type, variable and inlined-callee DWARF; separate work), `slotshare.rs` and `spill.rs` (die with Cranelift).

## Alternatives

- Do nothing: no measured speed or size win; the move only prepares deleting Cranelift and the stage 2 port, and lets the CLI-on-C thread target one place (`ms_link`). It is mechanical and reviewable alone; later, under pressure with the deletion, it is not.
- New `ms-link` crate: rejected by "fewer crates, not more"; it would also have to be deleted when the driver is ported.
- Port to C now: the lld embedding, fetch with TLS and archive unpacking, and the stub generators are 1000+ lines of working Rust that need `rustls`; porting needs a TLS and flate2 decision (libuv plus the existing libcrypto, or shelling out) that is a design question. Moving first keeps that decision out of a refactor.

## Stages

1. This PR: the move, green on `cargo nextest run --workspace` for `ms-build`, `ms-clif`, `ms-cli`, and `make verify`.
2. Later: port the driver (C in `libms` or a Manuscript module), then delete `ms-build`'s link module.
