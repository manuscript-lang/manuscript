# A facts dump from the C checker

## Summary

- Problem: `tools/ms/views.ms`, `inspect.ms`, lint, the guide and the language server read facts that only the Rust checker produces (`ms-tooling-dev facts`, `ms inspect`), so the Rust checker and `ms-tooling` cannot go.
- Change: `ms_check_dump --facts FILE...` prints the same fact JSON from the C checker's columns (`compiler/include/ms/facts.h`), field by field as the columns land, and a diff script compares each printed field with the Rust dump over the corpus.
- Decision requested: none; the coordinator asked for it.

## Status

Stage 1 implemented; 2026-11-20; checked against `origin/main` 814f41d8; reviewer: narrow to stage 1. The checker thread owns the columns, confirmed none are missing for tries, error type and calls, and left the printer to this thread.

## Problem

- The tools' input is one JSON document per program: per callable or type the key, file, kind, name, line, effects, error type, try count, resource scopes, calls, external calls, slots (name, type, passing mode, referenced types), result, receiver mode, and the flow steps (schema in `tools/ms/views.ms`).
- Verified: `compiler/tools/ms_check_dump.c` already loads the standard library and checks one file's bodies (`check_bodies_with_methods`), but prints only the checker's own dump formats.
- Only functions with `body_checked` set have columns (about 3300 corpus functions today).

## Design

- `compiler/src/check/dump_facts.c`: `ms_dump_module_facts(MsBuf *, MsCheck *, MsModId)` writes the JSON of `tools/ms/views.ms`. `ms_check_dump` gains `--facts`, which uses the same load and check path as `--bodies`.
- Each field comes from the nearest source: name, kind, file and line from the syntax tree; `slots`, `result` and `receiver` from the declaration plus its signature type (`ms_ty_show`) and the method access bits; `calls` from `call_callee`/`call_method`; `effects` from the declared-effect graph (`effect_reach.c`, `effect_directives.c`; `effect_scan.c` drops method and interface calls); `tries` is a syntax count of unary `?` in the body (`compiler/src/syntax/walk.c`, as `count_declaration` does in Rust); `error` is E of a `Result[T, E]` signature result; external calls are callees outside the project or calls with no callee fact; `scopes` waits on cleanup facts (not planned until closeable bindings are admitted); flows come from syntax plus the call columns.
- Scope of stage 1: single-file programs that import only `@std/` (the limit of `ms_check_dump` and of the Rust oracle `ms-tooling-dev`). A function the body pass did not claim is not printed and is counted in a `skipped` line on stderr; nothing is printed as a guessed zero value.
- `compiler/tests/facts-diff.sh` first requires the entity key set, kinds and lines to equal the Rust dump's (no waiver), then compares each supported field listed in its `FIELDS` set; a field joins `FIELDS` when its column lands. Fields not yet in `FIELDS` (`external`, `refs`, `flows`, `result_ownership`, `scopes`) are not compared, and the script prints how many entities and files it compared and skipped.
- The language server's list (diagnostics, symbols, uses, types, scopes, token classes) is a second dump over the same columns; it is a separate proposal once this one lands, with the same JSON writer.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `compiler/src/check/dump_facts.c`, `compiler/include/ms/dump.h` | new writer | `compiler/tests/facts-diff.sh` |
| `compiler/tools/ms_check_dump.c` | `--facts` mode | same |
| `crates/ms-tooling/src/bin/ms-tooling-dev.rs` | unchanged: it stays the oracle until the Rust views go | existing |
| `tools/ms/views.ms`, `inspect.ms` | unchanged: they read the JSON from either producer | `views-diff.sh` |

## Alternatives

- Do nothing: the tools keep the Rust checker as a build input.
- A flat-table entry point in `tool.h` instead of JSON: Manuscript tools already read JSON through `parse[T]`; tables suit tree walks, not entity records. A table form can sit on the same writer later.
- Wait for every column: nothing lands for weeks and the schema stays untested; per-field comparison finds schema mistakes now.

## Stages

1. Printer and diff script for key, kind, name, line, slots, result, receiver, tries and error type.
2. Calls, effects, then `external` (the hardest: Rust's call-target text), `refs`, `result_ownership`; scopes when cleanup facts exist.
3. Flows, then switch `views-diff.sh` and `inspect-diff.sh` to the C producer.
