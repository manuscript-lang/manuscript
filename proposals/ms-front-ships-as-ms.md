# The Manuscript front ships as `ms`

## Summary

- Problem: the Manuscript front (`tools/ms/main.ms`) is the intended `ms` for every command, but the archive and installers ship the Rust binary only, so nothing the front ports reaches users, and Rust code that the front replaces (`fetch.rs`, `edit.rs`) cannot be deleted.
- Change: the distribution ships two programs, `ms` (the front, linked with `libmstool.a`) and `ms-rust` (the existing Rust binary, renamed in the archive only). The front delegates uncovered commands to `ms-rust` beside it. Then the `packages.rs` end-to-end tests move onto the front and `fetch.rs` and `edit.rs` are deleted.
- Decision requested: none that changes the language; the CLI thread and Chinmay already directed "use `ms` as the front for all commands".

## Status

Stage 1 (this PR): packaging, installers, rehearsal and docs. Stage 2: tests move, Rust install/add/remove is deleted.

## Problem

- Install, add and remove already run in the front (#5330) and never answer "unsupported", but a user running the shipped `ms` still gets Rust's `fetch.rs` and `edit.rs`.
- `crates/ms-cli/src/fetch.rs` and `crates/ms-driver/src/project/edit.rs` stay because 13 end-to-end tests in `crates/ms-cli/tests/packages.rs` drive the Rust `ms install/add/remove`. Deleting them first broke those tests (tried, reverted).
- `bridge.ms` already delegates to `ms-rust` on the PATH, so the shipped layout and the front's expectations disagree.

## Design

- `tools/package.ms` builds the Rust CLI as before, builds `libmstool.a` with CMake (`ms_tool` target), builds the front with it, and archives `ms` (front) and `ms-rust`, plus the existing LICENSE and examples.
- `bridge.ms::rust_cli` looks for `$MS_RUST_CLI`, then `ms-rust` beside the executable, then `ms-rust` on the PATH.
- `install.sh` and `install.ps1` copy both files; the release rehearsal asserts `ms-rust` was installed; `rust-dist.yml` checks the glibc floor of both.
- The cargo binary stays named `ms`: 48 test files and about 95 Makefile and workflow references use `CARGO_BIN_EXE_ms` or `target/*/ms`, and renaming them gains nothing for users.
- Stage 2: `packages.rs` becomes a Manuscript test (`tools/ms/packages_test.ms`) run by the C pipeline job that already builds `libmstool.a`, with every test kept; no new CI job or shard.

## Evidence

- `ms run tools/package.ms` produced `dist/manuscript-rust-linux-amd64.tar.gz`; `ms run tools/dist-check.ms` printed `dist-check ok` with the front as `ms` (locally, linux/amd64).
- `make ms-cli-check` compares the front's exit statuses with Rust's on `tools/ms/cases.txt`.
- Removes in stage 2: `fetch.rs` and `edit.rs` and their callers.

## Alternatives considered

- Do nothing: the front stays unshipped; the Rust deletions stay blocked.
- Rename the cargo binary to `ms-rust`: touches every test and workflow for no user benefit.
- Make the Rust binary link `libmstool` and embed the front: needs the front in Rust or a second link path; larger, and the opposite of retiring Rust.

## Risks

- The shipped `ms` now needs CMake and Ninja at package time on all six legs (the native toolchain action already installs them; Windows ships them with the runner). Windows and macOS CI are dispatched on the branch before merge.
- Windows: CMake's default compiler may be MSVC, giving a different ABI than the gnullvm runtime; the front build on windows-amd64 and arm64 is unproven until the dispatched rust-dist run passes. If it fails, the fix is pinning the compiler in `package.ms`, not skipping the leg.
- Symlinked `ms` on macOS: `uv_exepath` does not resolve links, so the front falls back to `ms-rust` on the PATH.
- The front supervises `ms-rust` as a child: a signal sent to the front is not forwarded (#5009) and a child killed by a signal reads as 70. Exit statuses on the covered cases match (`make ms-cli-check`).
- `check_generic.c` zero-initialises two arrays: `-Werror=maybe-uninitialized` stopped `libmstool.a` from building with the local GCC.
- Two programs per archive: the installers write both before announcing success, and `ms` falls back to the PATH if `ms-rust` is missing.
