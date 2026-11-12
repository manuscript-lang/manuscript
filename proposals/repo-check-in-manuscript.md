# Repo-check text rules in Manuscript

## Summary

- Problem: `ms-repo-check` holds six rule modules in Rust that only read text, so repository invariants are written in a language the project is trying to replace for tooling.
- Change: move those rules to `tools/repo_check.ms`; keep the rules that need `ms_syntax` trees in the Rust binary.
- Decision requested: none (language and user-visible behavior unchanged).

## Status

Implemented 2026-11-12. Direction: move Rust code that Manuscript can do into stdlib and tools; keep Rust where its libraries are the solid foundation.

## Problem

- `release.rs`, `unsafe_boundary.rs`, `thread_affinity.rs`, `internal_externs.rs`, `portability.rs` and `layering.rs` (668 lines) only list files, read lines and compare strings.
- The tool crate is rebuilt whenever any of them changes, and a rule edit needs a Rust toolchain round trip.
- Other tools (`doctor.ms`, `conform.ms`, `count-check.ms`) are already Manuscript and run through `$(MS) run`.

## Design

- `tools/repo_check.ms` (542 lines) runs: extension and `.msversion` pin, workflow triggers, `unsafe` boundary, thread affinity, internal externs, portability (attributes, reserved names, case collisions, line endings, stdlib imports) and crate layering. It prints one success line or a sorted issue list and exits 1.
- Messages keep their wording. The allow-list files stay under `crates/ms-repo-check/`.
- `make repo-check` runs the Rust binary (nested matches, formatting, stdlib syntax, inline sources, stream names, impl adjacency, optional defaults, stages) and then `$(MS) run tools/repo_check.ms`.
- Not moved: rules over syntax trees (need `ms_syntax`, a Rust crate), and `licenses` (parses Cargo metadata through Rust libraries).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `tools/repo_check.ms` | new, the moved rules | `tools/repo_check_test.ms` (13 tests, ported from the deleted Rust unit tests); clean tree passes |
| `crates/ms-repo-check` | six modules removed, `main.rs` trimmed | `make repo-check`, clippy |
| `Makefile`, docs, wiki | wiring and path references | `make repo-check` |

Manual probes, run before the Rust rules were removed, that were all detected: `unsafe` in `ms-lower`, an unused internal extern, `Rc` in `ms-std-path`, a wrong extension version, a CRLF file, `aux.txt`, a case-colliding pair, an `ms-lower` to `ms-rt` dependency.

## Alternatives

- Do nothing: no user-visible gain; keeps 668 lines of text scanning in Rust. Cost of change is small, and the tool dogfoods the standard library.
- Move every rule: blocked, the AST rules need the Rust parser; exposing it to `.ms` is a larger change with no payoff here.
- Cost: the Manuscript half takes about 4 s warm versus near-instant incremental Rust; accepted because `make repo-check` also builds `ms` anyway.
