# Field views: a `var` record parameter is read and written in place

## Summary

- Problem: a function that takes `var flow: Flow` loads the whole 520-byte record at entry (`take Flow %0`), rebuilds it for every `flow.pos += 1` (`type.set`), and stores it back before every call or return (`put %0, v`). In Debug the record lives in 520-byte stack cells, so yaml `quoted.body` keeps a 2488-byte frame and `flow_value.body` 3256 bytes.
- Change: a MIR pass turns a record that is only a copy of a `var` parameter's memory into field loads and stores on the parameter's pointer, so the record is never materialized.
- Decision requested: none; no language change. Chinmay's target is frames "in the hundreds of bytes".

## Status

Proposal, 2026-11-23, checked against `e47e2b0d0b`. Review (skeptical subagent): revise. About 1 KB of `quoted`'s frame is spills (about 130 eight-byte words), so removing both 520 B cells gives about 1.3 KB, not hundreds of bytes; the chain parks the record in `slot Flow` temporaries (7 in `quoted`), which Stage 1 skips; unwind of a half-updated record and cancel mid-chain are unspecified (`mir_unwind_cells.c:131`, `mir_unwind_own.c:106`); `MIR_E_OWNERSHIP` `type.set` has never aliased memory for `copyelim`/`lastuse`. Not built until revised.

## Problem

Measured on `e47e2b0d0b`: `ms build` (Debug) of a program that calls `@std/data/yaml.ms` `parse`, `objdump` of the `sub rsp` in each function.

| Function | Frame |
| --- | --- |
| `flow_value.body` | 3256 B |
| `quoted.body` | 2488 B |
| `block_value.body` | 2360 B |

- `quoted.body` allocas (Debug IR): two 520 B cells (`Flow`), 22 x 16 B, 15 x 24 B, one 96 B, one 56 B; the rest is spills. The 520 B cells are the `Flow` chain of block parameters (`b17(%117: move Flow)`, `b18`, `b34`, ... eight of them) and the `type.set` results between them.
- MIR of `quoted` after `--opt`: one `%1 = take Flow %0`, 46 `type.set Flow` and 208 `type.get Flow` in the whole yaml module, and six `put %0, %v` before the calls and returns that need the record in memory. The record is inlined `advance(flow)`: `type.get Flow.chars`, `type.get Flow.pos`, then `type.set Flow.pos`.
- Release is unaffected by frame size but runs the same copies; the cost is the copy itself.

## Design

- Candidate: a value `x = take T p` where `p` is a `var` parameter pointer (or a slot used only by put and take), whose every use is `type.get`, `type.set` (a new value with one field changed), a block-parameter pass of such a value, `put p, x`, or a by-value argument of a call.
- Rewrite: while the chain is live, memory at `p` holds the current record. `type.get T.f x` becomes a load from `p + offset(f)`; `type.set T.f x, y` becomes a store of `y` to `p + offset(f)` and its result names the same memory; `put p, x` of the chain value is deleted; a by-value call argument keeps its copy (`take T p` just before the call).
- Fields that own memory (`List`, `String`, `Map`) are lent by `type.get`, as today; `type.set` of an owning field drops the old value first, as today. Only the record's own storage stops being copied.
- A chain is skipped when `p` could alias another use of the record in the function (a second `var` pointer, a call that receives `p` while the chain is live and is not one of the rewritten forms) or when any use is outside the list above. The test is the use list, nothing keyed to `Flow`.
- Ownership: `take` moves the record out of `p`; the rewrite keeps the record in `p`, so the unwinding and drop elaboration must see `p` as still owning it. The verifier runs after the pass.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/` new `opt_fieldview.c`, `opt_pipeline.c` | the pass, after inlining and `simplify` | MIR fixtures: `type.get`/`type.set` chain on a `var` param becomes loads and stores |
| `src/compiler/mir/mir_verify_own.c` | accept a record owned by the parameter pointer across the chain | `ms check` of a fault inside the chain (drop count) |
| `tests/conformance/fixtures/e2e/accept/` | var-record fixture with a fault and a cancel mid-chain | `make verify` |
| `bench/perf/` | before/after on yaml and toml parsers | dated result |

## Alternatives

- Do nothing: `quoted` stays 2.5 KB; the 20000-deep TOML nesting test already passes with 13 KB frames, so only the target frame size changes.
- Lend `Flow` to the helper functions in `yaml.ms` (`peek(flow)` borrows): already the case; the copies come from the mutating helpers.
- Restructure `yaml.ms`: move the rarely changed fields (`chars`, `codes`, `context`) into a nested record behind one reference so `Flow` is about 10 leaves. Smaller, no compiler change, but each parser written with a wide record hits the same cost.
- Hold fewer values (more `wide_leaves` tuning): measured no gain; two cells are already the minimum for a chain plus a callee result.
- Already tried and dropped: forwarding `put S,v; take S` across effectful instructions (frame 2488 to 2472 B), bulk-pop slot sharing (byte-identical).

## Stages

1. Pass for `var` parameter pointers with scalar-field updates; yaml `quoted` frame and all e2e green.
2. Owning fields and slots used only by put and take.
