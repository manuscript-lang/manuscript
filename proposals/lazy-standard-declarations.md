# Lazy standard-library declarations

## Summary

- Problem: every `ms check`, `run`, `build` and every agent call starts by parsing and declaring 47 of the 114 bundled files (430 KB of 1.2 MB), though a program imports few. That startup is 59% of a hello check.
- Change: load a native module when something imports it, like pure source modules already load. Then check bundled function bodies only when reached.
- Finding: the ceiling saves 2.9% of conformance wall time, under the 10% bar. Parked; nothing is built. Per-check gains (8 ms, 16% of instructions) do not justify a loader change.

## Status

Parked at Stage 0, 2026-11-15, checked against `7d4b8c2f`. Direction (lead): do the 40 ms floor first; build Stage 1 only if the ceiling saves 10% or more of the conformance corpus wall time, with one loading path and no owner tables unless a lookup needs one. Owner rule: no caches; redesign first.

## Problem

Measured on `7d4b8c2f`, release `ms`, callgrind of `ms check` of a one-line `print` program: 170.3M instructions, 46 ms median wall.

| Part | Instructions |
| --- | --- |
| `ensure_standard` (inclusive) | 101.3M (59%) |
| of which `parse_bundled` | 37.2M (22%) |
| of which `bundled_modules` (split, desugar) | 22.6M (13%) |
| of which register, declare, bind, stub checks | about 41M |
| `check_bodies` of the 15 bundled modules `print` reaches | 43.4M (25%) |
| analyses, project check, teardown | the rest |

- `build.rs` (`eager_modules`) marks eager every file that is not pure source, plus the extension modules and everything they import. A throwaway `eprintln!` in `parse_bundled` shows hello parses 47 files, including `os/fs.ms`, `net/http.ms`, `net/tls.ms`, `io/archive.ms`, `data/json.ms`, `os/process.ms` and their `internal/` twins, none of which it imports.
- `load_deferred` refuses a native module: `"is not pure source; build.rs must load it eagerly"` (`stdlib.rs:1568`). Native modules are eager because `Loader` runs once over all of them (`stdlib.rs:1600`): identities, declarations, implementations, receivers, defaults.
- A fresh process pays this on every run. The language server pays it once per session (hello is 96 ms cold and 1.3 ms warm).

Ceiling, throwaway patch (not correct in general): leave the domain modules (`fs`, `process`, `net`, `http`, `archive`, `crypto`, `json`, `regex`, `tls`, `websocket`, `url`, `ip`, `terminal`) out of the eager set. Hello goes from 170.3M to 142.6M instructions (-16%) and 46 to 38 ms. A program importing `@std/os/fs.ms` then panics with the message above, so the loader work is the real change.

Corpus ceiling (the case that decides): the 2,921 `tier-core` fixtures of `tests/conformance` that run correctly under that patch, `ms-conform run --corpus`, 4 cores, 3 alternating runs each. Base 62.8, 62.7, 61.9 s (median 62.7); patched 61.7, 60.9, 60.3 s (median 60.9). That is 1.8 s, 2.9%. The corpus time is builds, linking and running, not the front end. The other 294 fixtures reach a deferred module through a pure source module and crash under the patch, so they were left out; the real design would load them on demand.

Lookups without an import (read for this review): by-name lookups (`standard_symbol`, `standard("List")`, `time_type`, `sole_operation`) name prelude and extension types, all in the eager roots; `visible_in` (`types.rs:856`) shows a method only where its type is used, and a type only reaches a program through an import. Imports alone decide what loads, so owner tables are not needed.

## Design

One rule: **a bundled module is parsed and declared when a program, or a module already loaded, names it.**

- Roots that stay eager: the extension modules, `core`, `intrinsics`, and their import closure (about 21 files, 194 KB from a first count). Primitives and prelude types always resolve, so their receivers must be present.
- No owner tables: imports alone decide what loads (see Problem).
- `Loader` becomes incremental: `load_modules(new)` runs its phases over the newly loaded set against what is already declared. The import closure from `build.rs` guarantees a loaded native module never names an unloaded one, so no cross-module stub is needed.
- Trigger: `source_standard_dependencies` (`stdlib.rs:1441`) already walks a program's imports before checking, so natives load there, before any module is checked. Tools that list all declarations use `load_deferred_all`, which already exists.
- Stage 2: bundled function bodies are checked when lowering or a tool reaches them, as the effect scan and ownership already do (`analyze-the-standard-library-on-demand.md`). The library is validated when it is built, by a test that checks every callable.

Estimates (hypothesis until measured): Stage 1 reaches the ceiling above, hello about 142M and 38 ms. Stage 2 removes up to the 43M of bundled body checks that `print` does not reach, so hello about 100M and 25 to 30 ms. Programs that import the heavy modules gain less.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/build.rs` | eager set is roots and their closure only | existing |
| `ms-check/src/stdlib.rs` | incremental `Loader`, native deferral | each of the 114 modules imported alone: diagnostics and emitted MIR equal the old build |
| `ms-check/src/bundled.rs` | classification shared with `build.rs` | existing |
| `ms-lsp`, `ms-tooling` | use `load_deferred_all` where they list the library | existing LSP and `inspect` tests |
| `bench/perf/compile` | dated section | before and after |

## Alternatives

- Do nothing: 46 ms per check and 59% of it unrelated to the program.
- A snapshot of the declared library on disk: the types are `Rc` graphs, so it needs a serialization of all of them and an invalidation key, and loading it is still proportional to the library. Rejected in `analyze-the-standard-library-on-demand.md`; a cache by another name.
- Skip bodies when parsing (skim to the end of each block, parse when checked): helps the 22% parse share but only for modules whose bodies are never checked; it follows Stage 2, not before.
- A faster lexer and parser: 86 instructions per byte, and a smaller set of files parsed gives more than a faster one.

## Stages (parked)

1. One loading path: the eager roots are the first demand, and `load_deferred` loads native modules through the same `Loader`. If a batch and an incremental loader both have to stay, stop. No owner tables. Check: conformance corpus byte-identical on both backends, the 114-module differential, hello instructions and median of 15 wall runs.
2. Demand-checked bundled bodies. Check: a test that checks every bundled callable, plus the same measures. A Stage 1 result below 10% means stop and report.

Platform parity: the tables are generated at build time and platform independent; the differential runs on the six scheduled platforms.

## Open questions

None that change the language or user-visible behavior. One to verify in Stage 1: whether any extension or `impl` visibility depends on a module being loaded without an import (`method_visible`); the differential covers it.
