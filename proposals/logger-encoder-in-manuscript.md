# Write the logger encoder in Manuscript

## Summary

- Problem: `@std/log.ms` is a thin shell over the `ms-std-log` Rust crate through `stdlib/logcore.ms`; the crate only builds a JSON line the standard library can already build.
- Change: build the record in `log.ms` with `JsonValue` and `stringify`, replace the native gate with a flag in the transport's own state, and delete the crate, `logcore.ms` and their symbols.
- Decision requested: none beyond the direction already given; this records why it is safe.

## Status

Implemented 2026-11-01 on top of `main` at `4c5998a0` (#2184). Direction: "I don't see why we need these methods in Rust, we can just do them in Manuscript."

## Problem

Writing a record crossed into Rust four times: `new_state`, `child`, `line`, `line_json`, plus a `LogGate` object for a shut flag.

- The Rust side re-parses the fields text with `ms_std_json`, merges maps and calls the same `stringify` the `.ms` side calls first (`crates/ms-std-log/src/lib.rs`, 214 lines).
- Level numbering existed twice: an index 0 to 6 in `.ms` and Rust, and `(index + 1) * 10` written to the line.
- The surface was 11 `msrt_logcore_*` symbols in `crates/ms-rt/SYMBOLS.md` and a 115-line `stdlib/logcore.ms` of one-line forwards.

## Design

- `Logger` holds the threshold as the number written to the line (Trace 10 to Fatal 60, Silent 70), `timestamp`, `max_bytes`, bound fields as a `Map[String, JsonValue]` and the shared transport.
- A record is a `Map` in insertion order: `level`, `msg`, optional `time`, then bound fields, then call fields. `Map.add` replaces in place, which is the old "later value wins without moving the key" rule. `level`, `msg` and `time` in fields are dropped.
- Fields go `stringify` then `parse` to a `JsonValue`; an object contributes its members, anything else goes under `data`. The cost is the round trip the Rust side already made.
- Size: `max_bytes` 0 is `LimitExceeded`; otherwise `stringify` gets a budget of `max_bytes - 1` and the newline is appended. Errors map `LimitExceeded` to `LimitExceeded` and every other `JsonError` to `InvalidData`.
- Shutting a transport is a `closed` field in the `Shared` state next to the stream, checked under the lock each write already takes. `LogGate` goes away.
- `set_level` is now `var fn`, because a `Logger` is a value and no longer a handle to a shared native object. A copy keeps its own threshold, so a copy handed to a function no longer sees later `set_level` calls. Callers that used `let` must use `var`.
- `close` and `flush` now wait for an in-flight write on the same lock. A stalled stream delays `close`, but a file is never closed under a writer, which the lock-free gate allowed.
- The raw-text methods (`log_json`, `child_json`) were removed in #2160, so the cases that fed invalid or non-object JSON text no longer exist.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/log.ms` | encoder, level numbers, gate flag | `tests/e2e/testdata/stdlib/log.ms` |
| `stdlib/logcore.ms`, `stdlib/internal/logcore.ms` | deleted | `make docs-check` |
| `crates/ms-std-log` | deleted with its 1752-line oracle | table test below |
| `crates/ms-native`, `Cargo.lock`, `crates/ms-rt/SYMBOLS.md` | drop the crate and 11 symbols | `ms-cli` `runtime_symbols` |

## Evidence

- Equivalence (measured): a throwaway replay of the 1751 oracle cases through the new logger matched all 1011 cases that use object fields. The other 740 feed invalid or non-object JSON text, which has no API now.
- Coverage kept: a 36-case table in `tests/e2e/testdata/stdlib/log.ms` pins limits, thresholds, escapes, bound fields and every error.
- Speed (measured, `ms run`, 400k records, half with three fields): 440 ms before, about 520 ms after, so 1.1 to 1.3 microseconds per record.
- Code removed: about 2400 lines (crate sources and oracle harness 411, oracle data 1752, `logcore.ms` plus its internal helper 116) for about 130 added lines of `.ms`.
- The replay script was a throwaway run before the oracle was deleted; the table test is the retained evidence. This is not a performance PR, so no `bench/perf` baseline was run.

## Alternatives

- Do nothing: keeps a crate, 11 symbols and the second level numbering for no capability.
- Keep the encoder in Rust and only drop the gate: removes one object, leaves most of the layer.
- Add a typed `JsonValue` builder that skips the stringify/parse round trip: faster, but a larger JSON API change for a logger that spends about a microsecond a record.
