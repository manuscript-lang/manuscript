# Load pure source standard modules on first import

## Summary

- Every `ms` process parses and registers all 98 bundled standard modules (about 1.06 MB) before it checks anything, though a typical program imports a handful.
- Load the pure source modules (bodies only, no native declarations, no `extern type`) that nothing eager imports when a program first looks them up; `build.rs` picks them by parsing the standard library.
- Internal only: no language, diagnostic or output change.

## Status

Implemented, 2026-11-02, on top of bea0427a. Skeptical review: build; it asked for an exact pure-source check in `load_deferred`, one extension list and corrected counts, all applied.

## Problem

- Measured (callgrind, release `ms check` of a two-line `fn main`): 302.7M instructions; `ensure_standard` is 53% of them and parsing the standard library 35%.
- Measured: wall time 87 ms per check of that file (30 runs, x86-64 container). The conformance corpus starts about 4,000 such processes, the e2e suite and editor tests more.
- Verified: `stdlib::load` (`crates/ms-check/src/stdlib.rs`) parses every entry of `SOURCES`, then `Loader::register` records a pure source module by storing it in `source_modules` and declaring stubs for its exported types. Nothing else uses a pure source module until a program imports it.

## Design

- `crates/ms-check/build.rs` parses each bundled file with `ms_syntax` and marks it eager when it is not pure source (`bundled::is_pure_source`), is an extension module, or is imported, directly or not, by an eager module. `SOURCES` gains that flag.
- `load` parses only eager entries and keeps the rest as text in `World::deferred`.
- `standard_source_module`, `standard_module_symbol` and `source_type` call `load_deferred(path)` first, which parses and registers that one module exactly as `load` would.
- Listings that need everything (`standard_modules`, `standard_module_names`, `ensure_all_sources`) load all deferred modules first, so editors, `ms guide` and import hints see the full library. `World::sources` stays in file-name order.
- Invariants, each enforced:
  - A deferred module registers nothing global: no native symbols, no `extern type`, no intrinsic or receiver binding (`load_deferred` asserts `is_pure_source` on what it parses).
  - No eager module can name a deferred one: the eager set is closed under imports (`build.rs`).
  - `crates/ms-check/src/bundled.rs` holds the classification (`decl_has_body`, `is_mixed`, `is_pure_source`) and `EXTENSION_MODULES`; `build.rs` includes the same file, so the build and the loader cannot disagree. `ms-syntax` becomes a build dependency of `ms-check` (a workspace crate, no new external dependency).

Result: 56 of 98 files (about 600 KB) defer. A program pays for what it imports: `tests/e2e/testdata/stdlib/router.ms` still loads its deferred dependencies. Paths that list the whole library (unknown-name hints, editors, `ms guide`) load everything, as before.

| `ms check` of a two-line file | Before | After |
| --- | --- | --- |
| Instructions (callgrind) | 302.7M | 192.5M (-36%) |
| Wall, mean of 30 | 87 ms | 47 ms |

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/build.rs` | parse stdlib, emit the eager flag | build fails on a parse error |
| `crates/ms-check/src/bundled.rs` | shared classification | used by both sides |
| `crates/ms-check/src/stdlib.rs` | `deferred`, `load_deferred`, `bundled_modules` | `pure_source_modules_load_on_first_lookup`, conformance, e2e |
| `crates/ms-tooling/src/guide/api.rs` | reads the three-field `SOURCES` | `ms guide` tests |

## Alternatives

- Do nothing: every process keeps paying about 40 ms and 110M instructions for modules it never imports, about 160 s of CPU across the corpus's 4,000 processes; it is the largest fixed cost of a short check.
- Cache the parsed standard library on disk: saves more, but adds a cache format, invalidation and a writable location to every command. Lazy loading keeps one code path.
- Decide laziness at run time from the text (`extern`, `...`): tried first; `intrinsics.ms` declares native interfaces with neither marker and the loader broke. Parsing at build time is exact.
- Defer native modules too: they feed the global symbol table, prelude and receiver bindings, so deferring them would need demand-driven resolution of the whole loader. Not worth it before this lands.
