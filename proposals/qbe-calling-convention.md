# Calling convention and value flattening for the QBE debug backend

## Summary

- Problem: QBE returns one value and has no multiple results, but MIR values are flattened into several scalar leaves and the Cranelift backend passes and returns them as many scalars.
- Change: the QBE emitter uses the LLVM emitter's convention (`crates/ms-mir-llvm/src/abi_llvm.rs`) so one convention serves every backend: values of at most 16 bytes travel as scalar leaves, larger ones by pointer, and a result of more than one leaf goes through a hidden result pointer.
- Decision: approved by the coordinator for Chinmay on 2026-11-20 ("one convention across backends is what we want").

## Status

Proposal, 2026-11-20, checked against `b9c83b5dd`. No independent review: the change is one component (`compiler/src/emit_qbe.c`) and copies a convention that already ships.

## Problem

- Verified (`compiler/src/emit_qbe.c`): the emitter handles only `Int`, `Bool` and `Float` values. A `String` is two leaves, a list three, an optional a flag and a payload.
- Verified (`crates/ms-clif/src/cg.rs:328`): Cranelift signatures list every leaf as a parameter and as a return, which QBE cannot express for results.
- Without one rule for parameters, results and calls into the runtime, each op that touches an aggregate would invent its own.

## Design

- A MIR value is a run of QBE temporaries, one per leaf (`%v7.0`, `%v7.1`), named from the leaf index; a one-leaf value keeps the name `%v7`. Leaf types come from `mir_leaves` (`ms/mir_layout.h`): `i64`, pointer and sized integers are `l`, booleans `w`, `f64` `d`, `Float32` `s`.
- Parameters: a type of at most 16 bytes (`mir_type_mem`) is passed as its leaves in order. A larger type is a pointer: borrowed, moved and `var` all pass the address of the caller's slot, and `var` is updated in place (the final value MIR returns after the result becomes a store at each `ret`).
- Results: zero leaves return nothing; one leaf returns it; more than one is written through a hidden first parameter `l %sret` that the caller points at a stack slot sized by `mir_type_mem`.
- Runtime calls keep the C ABI recorded in `ms-rt-abi`: aggregates by pointer, constructed aggregates through a trailing output pointer.
- Function addresses, closures, vtables and anything the runtime calls keep a thunk with the leaf signature that forwards to the internal body, as the LLVM path does.
- Memory: slots (`Slot`), `Load`, `Store`, `Put` and `Take` use QBE `alloc8` and typed loads and stores at the offsets `mir_mem_layout` gives. Sized integers load sign- or zero-extended and store truncated.
- First slice: records of scalars (`TypeNew`, `TypeGet`, `TypeSet`), slots, loads and stores, and the sret rule, tested by a MIR program per rule through `compiler/tests/qbe-run.sh`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `compiler/src/emit_qbe.c` | leaf temporaries, parameter and result rules, memory ops | `compiler/tests/qbe/*.mir` with expected exit status |
| `compiler/include/ms/emit_qbe.h` | takes the layouts it needs | unchanged tests |

## Alternatives

- Do nothing: only scalar programs build with QBE, so the corpus cannot run.
- Aggregates as QBE `type` values (`:T`): QBE then follows the platform's struct ABI, which differs between SysV, Apple arm64 and Windows, and is the part QBE has no Windows arm64 port for. Explicit leaves and pointers keep the convention ours on every platform.
- Pass everything by pointer: simpler, but every scalar-like value (a string, an optional integer) round-trips memory, which the 16-byte rule avoids.
