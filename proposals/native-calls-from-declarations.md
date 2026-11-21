# Native calls from their declarations

## Summary

- Problem: the C lowering lowers `List` methods by matching the method name (`lst_method`, `lst_append` in `compiler/src/check/lower_list.c`). Every new native needs a new case, and the Rust lowering does the same in `crates/ms-lower/src/native/*.rs` (3555 lines).
- Change: a bodiless native `fn List[T].name(...)` lowers as an ordinary call of the runtime function it declares, with the ABI read once when the standard library loads. The call site never looks at a name.
- Speed comes from general inlining of small functions, not from a pass that knows which functions are cheap.
- Decision requested: the binding syntax in the declaration (open question 1), and whether lower-diff may differ from Rust where Rust inlines (open question 2).

## Status

Proposal, 2026-11-21, checked against `main` after #5265. Direction (Chinmay): special-casing the standard library does not work; checking every implementation by name slows compilation.

## Problem

- `xs.length()` and `xs.append(v)` are lowered by comparing the method name with a list of strings, per call, in both compilers.
- `stdlib/collections/collections.ms` has 19 `fn List[T]` rows, most of them natives; Map and Set add more. Each needs a case today.
- The runtime already has the other side: `runtime/include/ms_rt/list.h` has 47 `msrt_list_*` functions, each with an `ms-sig:` comment giving its ABI (`v: *const VecVal`, `d: ElemDesc`, `out: *mut u8`).

## Design

- A native row names its runtime function. Resolve it once per declaration when the standard library is loaded (`ms_check` row, next to `call_method`), not per call. Compile cost is one lookup per declaration.
- The ABI of each parameter comes from the `ms-sig` type, one rule per type, independent of the method:
  - `*const VecVal` / `*mut VecVal`: the receiver, borrowed or by reference for a `var` receiver.
  - `ElemDesc`: the type descriptor of the type argument (`typedesc`, as `lst_append` emits today).
  - `i64`, `f64`, `bool`: the argument value.
  - `*const u8` argument: a pointer to the argument value; `out: *mut u8`: a slot for the result.
- A call is `MOP_CallRt` with that signature. Ownership follows the declaration: the parameter and result modes the checker already records.
- Small natives (`length`, `is_empty`, `get`) are made fast by inlining, not by naming them:
  - Option A: the runtime is also built as bitcode and linked into Release LLVM builds, so LLVM inlines `msrt_list_*` bodies. Debug (Cranelift) pays a call.
  - Option B: a general MIR inliner for functions under a size bound, with the runtime bodies available as MIR. Larger, but backend independent.
- The C lowering then has one native-call path and no list names. `lst_method` and `lst_append` are deleted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/*.ms` | The binding named in the declaration (open question 1) | `ms search_symbol`, stdlib parse tests |
| `compiler/src/check` | Row records the runtime function and per-parameter ABI at load | `check-diff.sh` tables |
| `compiler/src/check/lower_body.c` | One native-call path; delete `lst_method`, `lst_append` | `lower-diff.sh`, `compiler/tests/lower/list_methods.ms` |
| Back end | Option A or B | `bench/perf/` before and after |

## Alternatives

- Keep the name tables (today): rejected by Chinmay.
- A MIR pass that folds `msrt_list_len` into `list.len`: it is keyed on names, the same special case.
- Intrinsic annotations on every native: still a per-name table, only moved into the stdlib.

## Open questions

1. How a declaration names its runtime function. Convention `msrt_<type>_<method>` needs no syntax but breaks for renamed or shared functions; an explicit attribute adds syntax to the language, which is Chinmay's call.
2. Rust inlines `length` and `get` as MIR ops, so a function using them has a different MIR shape in C until inlining runs. `lower-diff.sh` compares the text, so it would differ. Exempting those functions from the comparison counts as gating a test and needs Chinmay's approval. The alternative is to land the inliner first so both shapes agree.
3. Option A or B for inlining.
