# Check bundled standard bodies when reached

## Summary

- Problem: every `ms check` and `ms lint` type-checks and ownership-checks the body of every bundled standard function it loads, though the bundled library is fixed per binary and a program reaches a small part of it.
- Change: every run (`check`, `lint`, `build`, `run`, `test`, `bench`, `inspect`, the language server) sets standard bodies aside and checks, and ownership-checks, only those a reference reaches, transitively. Reach includes what lowering calls without a written reference (below). `ms check <file> --std` loads every bundled module and checks every body, and the `std_full` test runs it.
- Decision requested: none; no language or output change.

## Status

Implemented for analysis; extended to build, run, test and bench 2026-11-25. Direction from the review lead: reachability-driven checking, `--std` as the full gate, lowering must only reach checked callables, with a verifier assert. Owner direction 2026-11-25: "let's do lazy checking of stdlib". Review: self-review against the do-nothing and cache alternatives (below); no other model consulted.

## Problem

Measured on a trivial `fn main() Void: return` (release build, callgrind instructions, 5-run median wall):

| Step | Before | After |
| --- | --- | --- |
| `ms check` | 152M instr, 38 ms | 60M instr, 15 ms |
| 60 e2e accept files, total | 9.79G instr | 4.0G instr |

About 58% of the trivial-file cost was checking bodies of prelude and imported standard modules that no line of the program calls. A broken standard body still fails the build that produced the binary, through `std_full`.

## Design

- `ms_check_defer_std_bodies` (check/lazy_std.c) moves each standard function and method body into a side table keyed by (module, node) and marks the function `deferred`.
- A reference to a deferred callable found in a checked body, or in a call fact, restores it. `ms_check_restore_reached` checks restored bodies and scans them for more references until none is new.
- A deferred method is not bodiless: `MsFunc.deferred` keeps `body_method_ref` from classifying it as native.
- Diagnostics inside unreached standard bodies are not produced by analysis runs. User-module diagnostics are unchanged: 2767/2767 check fixtures and 156/156 command fixtures agree.

## Safety

- `lower_init` aborts when the program was checked lazily; `reserve` aborts when an instance targets a `deferred` function. Build, run, test and bench use `ms_check_graph`, so neither fires in a correct build.
- `--std` takes the eager path over every `@std/` source, so a parse, type or ownership error in any bundled body fails `ctest -R std_full` on the PR that introduced it.

## Extension to build (stage 2)

Lowering calls some standard functions that no written reference names. The reach scan (`check/lazy_std.c`) restores them from one table, `check/hooks.h`:

- Hook methods: `close`, `clone`, `equals`, `hash`, `compare`, `to_string`, `to_json`, `entries`, `values`, `next`, the arithmetic operators and the fixture hooks. For every type that appears in a checked body (an expression type, a call's type argument, a binding or parameter), the methods with these names on that type's definition or builtin are restored, and so are the types it is made of (arguments, fields, cases, read as declared so a recursive generic type ends). `lower_named_method` faults on any other name, so a new hook cannot be added without the table.
- Roots: the functions lowering calls by name (`msstd_status_error`, `status_error_text`, the test and bench drivers).
- Defaults: a native function or record type whose parameter or field defaults call functions is listed, so reaching it scans its defaults.
- Views and bounds: `ms_check_view_targets` and `ms_check_instantiation_targets` match a method by the head of the receiver (its definition, or its builtin for `Bytes`, `String`), not only by definition; matching ignores type arguments, so it restores at least what lowering calls.
- `ms_func_has_body` is the one question "does this function have source": a deferred body counts. `reserve` and the vtable builder use it, so a missed edge faults at the name instead of silently treating the method as native.

Completeness is checked by running the whole corpus with lazy build: 663 run, 768 test and 47 three-module fixtures, the command fixtures, `ctest` (leak, bench, missing-tool programs). A missed edge is a fatal that names the function, never a wrong program.

## Measured (build, debug)

Callgrind instructions of `ms build a.ms --build-type Debug`, a program that writes one line (`ci` preset, one run):

| Part | Eager | Lazy |
| --- | --- | --- |
| Front end (`ms_checked_input_load`) | 135.5M | 75.5M |
| of it, ownership check | 64.5M | 15.9M |
| of it, parsing the bundled sources | 35M | 35M |

Parsing is now the largest front-end cost and is not touched here.

## Alternatives considered

- Do nothing: keeps 58% of trivial `check` and `lint` time spent on code the user never wrote or called.
- Serialize checked std summaries at build time: the checker state is pointer-rich (types, symbols, facts, ownership masks); a stable snapshot format is a large new layer for the same win.
- Check once per process in the LSP: already amortized there; unrelated to the CLI start-up cost.
- Lazy checking in build too: done in stage 2 above, with reachability closed over the hooks lowering uses.
- Check on demand inside lowering: ownership results of a callee feed its callers' moves, so a body checked late would change code already lowered.
- Restore every method of every reached type: simpler, but pulls in the whole of a type's methods (and what they call) for one use.
- A persistent cache of checked standard facts: pointer-rich state, a new layer, and a per-binary invalidation problem; reach-driven checking removes the work instead.

## Testing

`ctest` (31 tests, `std_full` new; `lsp_completion` fails on main), conformance parse 1461, check 2767, command fixtures 156, repo-check, run 607 of 608 (`net-close-releases-socket` fails under parallel load, passes alone).
