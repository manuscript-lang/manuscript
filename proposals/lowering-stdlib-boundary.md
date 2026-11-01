# Keep standard-library knowledge out of lowering

## Summary

- `ms-lower` (checked HIR to MIR) hard-codes standard-library knowledge: `HAND_LOWERED` (19 symbol/identity pairs), `HANDLE_FUNCTIONS` (13), about 20 top-level identity arms in `native.rs`, 5 in `closure.rs`, plus type- and symbol-name couplings in `text.rs` (decimal, timestamp, Duration formatting), `json.rs` (`@std/net/net.ms` Url/IpAddress/Cidr, Duration), `close.rs` (`SharedGuard`) and `expr.rs` (Decimal literals, Duration record). Most of the ~389 `msrt_`/`msstd_` literals are generic runtime calls, not std knowledge.
- Change: stage the removal. Stage 1 moves every std-specific lowering behind one table in one `stdlib/` directory with one dispatch point shared by direct calls and function values. Later stages replace table entries with `.ms` source over plain externs and delete the Rust.
- No language, grammar, ABI or user-visible change.
- Decision requested: none (internal). Stage 1 is built after review; later stages are go/no-go per entry.

## Status

Proposal, 2026-10-31, checked against `9cf35d57`. Triggered by the maintainer asking why lowering knows about html, fs and serve, and asking for a sound boundary between compilation layers. Direction: "Manuscript first, Rust limited to small general runtime primitives".

## Problem

- Layering: `ms-check` owns stdlib declarations, `ms-std-*` own the runtime, `ms-lower` should map any checked extern to MIR from its signature. Today it also contains stdlib-specific code: `html.rs` 314 lines, `fswalk.rs` 215, `httpserve.rs` 222, `codecstream.rs` 389, `natiface.rs` 1356, plus arms in `native.rs`, `random.rs`, `rtcall.rs`, `mapset.rs`.
- `closure.rs` repeats five of `native.rs`'s identity arms for function values (`io/stdout|stderr`, `time/clock|wall_clock`, `html/parse`, `json/*`, `io/read_all|copy`). Adding or renaming a std function means editing `.ms`, `ms-std-*`, and two or three dispatch sites that nothing connects.
- A stale plain extern already fails at compile time (`rt_sig` has no symbol). A stale `HAND_LOWERED` key does not: it silently becomes a plain extern.
- Not all of it is stdlib knowledge. `json/parse` and `json/stringify` generate code per user type (typed decode/encode); that is a language feature and stays in lowering. Also `collections/*`, `core/panic`, `math/*`, `shared/share` are language-level natives. The target is the stdlib-specific remainder.

## Classes of std-specific lowering

| Class | Examples | Why hand-lowered | End state |
| --- | --- | --- | --- |
| Handle interfaces | `io/stdin`, `fs/filesystem`, `net/network`, `time/clock` (`natiface.rs`) | interface value over a runtime handle | table in `stdlib/`, later `.ms` impl over handle externs |
| Tree/record copy | `html/parse` | copy runtime tree into `HtmlNode` | `.ms` over kind/child accessor externs |
| Option flattening, callback wrapping | `fswalk`, `httpserve`, `codecstream` | record to flag word; closure to code word | `.ms` wrapper flattens; callback wrapper stays one general lowering rule |
| Selection by name | `crypto/*`, `archive/*` digest and stream picks | symbol chosen by enum case | `.ms` match calling plain externs |

## Design

Review (independent, 2026-10-31) found moving files removes no logic and the duplication is small; verdict REVISE. Stage 1 is therefore re-scoped: no file move; one registry merging `HAND_LOWERED`, `HANDLE_FUNCTIONS` and the five `closure.rs` arms, plus the stale-key test below. The move into `stdlib/` and the couplings above are addressed by the later `.ms` stages, not by relocation.

Original stage 1 (superseded):
- Create `crates/ms-lower/src/stdlib/` and move `html`, `fswalk`, `httpserve`, `codecstream`, `natiface`, the std arms of `random`, and the crypto/archive tables into it.
- One `stdlib::lower(identity) -> Option<Lowering>` registry keyed by the identity. `native.rs` direct calls and `closure.rs` function values both ask it; the duplicated arms disappear. `HAND_LOWERED` moves into the registry so symbol and identity are written once.
- `ms-lower` outside `stdlib/` never names a std module. `make repo-check` gains a guard: no `"<std module>/` string literal outside `stdlib/`.
- A unit test walks every `extern` in `stdlib/*.ms` and asserts it is either in the registry or marshals as a plain call, so a stale symbol fails in tests.

Later stages, one entry or class per change, each with its own go/no-go:
- Move a class to `.ms` and delete its Rust only when generated MIR for the unchanged programs is equal or better and the runtime keeps its ABI. Candidates in order of risk: crypto/archive selection, `html/parse`, `fswalk` flattening, handle interfaces, `httpserve` and `codecstream` callbacks.

## Alternatives

- Do nothing: the strings work today. Cost is the duplicate dispatch and unchecked symbol drift above; it loses as the stdlib grows in `.ms`.
- Separate crate `ms-lower-std` plugged in by `ms-build`: the strongest boundary, but `FnLower`, `Val`, `NArg` and the builder would become public API, and stage 1 already gives the one-directory seam. Revisit if the directory still churns.
- Go straight to `.ms` for everything: needs a general callback and handle mechanism first; unproven (see go/no-go).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower/src` | move files, add registry, delete duplicate arms | existing `ms-lower`, `ms-cli` e2e, conformance; MIR dump of the e2e corpus before/after equal |
| `crates/ms-repo-check` | guard against std names outside `stdlib/` | repo-check test |
| `stdlib/*.ms`, `ms-std-*`, `ms-check`, `ms-clif` | unchanged in stage 1 | |

## Verification and go/no-go

- Stage 1: byte-identical MIR text for the e2e and conformance corpus, `cargo clippy`, `cargo fmt`, `cargo nextest run --workspace`, `make repo-check`. Stop if equal MIR needs behavior edits.
- Later stages: compare MIR, binary size and the `bench/perf` suite for any entry moved to `.ms`.

## Open questions

None.
