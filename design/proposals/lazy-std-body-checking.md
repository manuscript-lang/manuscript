# Check bundled standard bodies when reached

## Summary

- Problem: every `ms check` and `ms lint` type-checks and ownership-checks the body of every bundled standard function it loads, though the bundled library is fixed per binary and a program reaches a small part of it.
- Change: analysis runs (`check`, `lint`) set standard bodies aside and check only those a reference reaches, transitively. `ms check <file> --std` loads every bundled module and checks every body, and the `std_full` test runs it. Build, run, test and bench stay eager.
- Decision requested: none; no language or output change.

## Status

Built. Direction from the review lead: reachability-driven checking, `--std` as the full gate, lowering must only reach checked callables, with a verifier assert.

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

## Alternatives considered

- Do nothing: keeps 58% of trivial `check` and `lint` time spent on code the user never wrote or called.
- Serialize checked std summaries at build time: the checker state is pointer-rich (types, symbols, facts, ownership masks); a stable snapshot format is a large new layer for the same win.
- Check once per process in the LSP: already amortized there; unrelated to the CLI start-up cost.
- Lazy checking in build too: lowering walks bodies and expects checked facts; the assert keeps that boundary explicit instead.

## Testing

`ctest` (31 tests, `std_full` new; `lsp_completion` fails on main), conformance parse 1461, check 2767, command fixtures 156, repo-check, run 607 of 608 (`net-close-releases-socket` fails under parallel load, passes alone).
