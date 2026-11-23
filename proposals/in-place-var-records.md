# A `var` record is edited where it lies, from lowering on

## Summary

- Problem: lowering turned every field update of a `var` record into a new record value (`type.set`), threaded it through block parameters and `take`/`put` pairs around calls, and `opt_fieldview` (721 lines) tried to turn that chain back into field stores. It covered `var` parameters only and needed three fix PRs in one day (#6672, #6688, #6695 and the ICE fixes inside them).
- Change: a `var` record has one home, a frame cell for a local and the caller's pointer for a parameter. `x.f`, `x.f = v` and `f(x)` lower to a field address plus a load, a store or a lend. No value chain exists, so `opt_fieldview` is deleted.
- Decision requested: none; no language, stdlib or syntax change. Chinmay, 2026-11-23: "why are we not just updating the fields inline?"

## Status

Built and merged with this proposal, 2026-11-23. The skeptical review asked for params before locals, partial moves and a measurement first; all three are covered below.

## Problem

yaml parse, `ms test` build (task-starting programs, `ci` preset, `/tmp/h/frames.sh` over `objdump`), frames before:

| Function | Before | After | What filled it |
| --- | --- | --- | --- |
| `block_value` | 6.0 KB | 4.1 KB | four `slot Flow` and held `Flow` cells |
| `inline_value` | 4.2 KB | 3.6 KB | six `slot Context` and `Flow` cells |
| `flow_value`, `quoted` | 6.2, 2.1 KB | same | already handled for parameters |

- The pass saw `var` parameters only; a local `var flow = Flow(...)` that is edited and lent was the same chain and nothing recovered it.
- Each shape the pass recognised (record lend, field lend, nested edit, whole-field replace, borrowed call) was found by reading rejected MIR; the next unrecognised shape silently kept a 28 KB frame.

## Design

- A `var` parameter of record type is the caller's pointer (`fn_closing_param`, the machinery lambda-changed parameters already used): no entry `take`, no exit `put`.
- A mutable record local bound to a fresh value gets a `slot` and the scope's cleanup (`fn_bind_closing_in`), as a resource local does.
- Reads: `x.f` is `ptr.field` and `load` (`fn_read_field_in_place`). A field moved out of a parameter's record is `load` and `move.out`, and a later assignment to it drops nothing (`moved_fields`).
- Writes: `x.f = v` is drop-old or close-old, then `store` or `put` over the field, adjacent with no fault point between (`fn_store_field_in_place`).
- Lends: `f(x)` and `f(x.g)` pass the cell's or the field's address (`fn_field_address`); nothing is moved out and filled back.
- Alignment: a record keeps all leaves in one run, so a multi-leaf field after a bool starts off its own alignment and its cell differs from the record's bytes. `field_cell_exact` accepts a field only when it is one scalar leaf or follows whole-word fields; other fields keep the take/put path. Making every field its own cell in the layout would remove the gate, but the flat run is shared by records nested in records and optionals, so it is a layout change of its own.
- Unwind: a slot parameter's contents stay the caller's (`from_caller`); `ptr.field` of it counts as a borrow (`uw_bsv_field_borrowed`).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `lower/lower_func.c` | record `var` parameters take the closing-slot path | `var-record-*` accept fixtures, yaml, toml, html, json e2e |
| `lower/lower_field.c` | `fn_field_address` for parameters, `field_cell_exact`, in-place read and store | stdlib sweep, Debug and Release |
| `lower/lower_stmt.c`, `lower_expr.c` | member assignment and read use the address; mutable record locals in a cell | drop-count and cancel fixtures |
| `opt/opt_fieldview.c` | deleted (721 lines) | frames equal with and without the pass before deletion |

## Alternatives

- Do nothing: `block_value` and `inline_value` stay 0.6 to 1.9 KB larger and a new shape returns to 28 KB.
- Extend `opt_fieldview` to locals: smallest version, but recovery after the fact keeps finding new shapes (#6652 alone broke three fixtures).
- Box records over a size: an allocation per record, and the chain stays; a separate lever.
- Copy-on-write records: a runtime representation change for a lowering problem.

## Remaining

- Fields the alignment gate refuses, and locals not bound from a fresh value, keep the old path; they are the next candidates once the layout puts fields in their own cells.
