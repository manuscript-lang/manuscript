# Read constant lists from static data

## Summary

- Problem: every read of a module constant list (`table[i]`, `table.length()`, `for x in table`) allocates a list, copies the data into it and frees it. In an inner loop that is the whole cost.
- Change: a reference to a constant list of scalars is a borrowed view (`cap == 0`) of the constant's static data. A use that keeps or changes the list clones it, as for any borrowed value.
- Decision requested: add the op `list.const.view` and lower constant references to it. No language change.

## Status

Implemented 2026-11-25 in the C compiler: `fn_constant_list_view` in `lower_list.c` lowers a reference to a list of integer literals to `list.const.view` (the MIR op, verifier and emitter were already present); fixture `accept/constant-list-view.ms`; found by the HTML entity port ([result](../../bench/perf/pure-utilities/results-2026-11-25-html-entity-in-manuscript.md)). Floats, booleans and non-literal elements still rebuild the list. Original proposal, 2026-11-16, against `main` 2b8a689e. Fixes #4199. Removes no documented behavior: `documentation/core-language/modules/declarations.md` says each use of a constant evaluates its initializer in place, so a list constant is always fresh. A view is not observable: nothing can write it, and a use that could observe sharing gets a copy.

## Problem

Measured with `bench/perf/image-codecs` (2048 by 2048, one core, Linux x86-64, `main` 2b8a689e):

- JPEG decode and encode index two constant tables (`jpeg_dct_matrix`, 64 entries; `jpeg_zigzag`) in the inner multiply-add of the 8 by 8 transform. In the 256 by 256 callgrind profile each of those reads was an `msrt_alloc`, a memcpy and an `msrt_free`: about a million `msrt_free` calls per image.
- MIR before: `%t = call @jpeg_dct_matrix ()`, `list.get %t, i`, `drop %t`, per element.
- A hand hoist (`matrix := jpeg_dct_matrix` once per call) reached about the same gain, so the view's value is that callers need no convention, and reads outside a hoistable spot (CRC tables, S-boxes) are fast too. Measured on this change without the hoist: decode 1784 to 441 ms, encode 2302 to 326 ms at best of 3 (Go 96 ms, 183 ms).

```ms
table := [3, 1, 4, 1, 5, 9, 2, 6]

fn sum() Int:
    var s = 0
    for i in 0..8:
        s += table[i]
    return s
```

## Design

- `ms-lower` (`expr.rs`): a reference whose resolution is a constant, whose initializer is a list literal of scalar literals (`const_scalar`, already used for `list.const`), lowers to `list.const.view` and is not owned (`Val.own = false`). Any other constant keeps the call.
- `list.const.view` yields `(pointer to static data, length, 0)`. Capacity 0 is the existing marker of a borrowed list (`slice` of a lent list, `bytes.lit`): `drop` and `list.release` already skip it.
- Ownership: the result mode is Borrow (`Module::result_mode`), like `str.lit` and `bytes.lit`, so the verifier expects no drop. `Lowerer::owned` clones it, as it already does for those two ops, so `var t = table`, `return table`, a field initializer and a moving argument each get a fresh list, and `t.append(7)` writes the copy.
- Backends: Cranelift and LLVM emit the data address, the constant length and zero, reusing the static data `list.const` already declares (`ms.list.N`). The MIR interpreter treats it as `list.const`.
- No new analysis, pass or runtime function.

## Components

- `ms-mir`: `Op::ListConstView`, `Builder::list_const_view`, verifier, `result_mode`, `range.rs` length, `copyelim.rs`, interpreter.
- `ms-clif`, `ms-mir-llvm`: one arm each, and the LLVM module constants (`consts`).
- `ms-lower`: `constant_view`, and `const_scalar_as` (an item of another module's constant is typed by the list type, not by the current module's tables).

## Alternatives

- Do nothing: every table in `stdlib` and in user code (CRC tables, S-boxes, direction lists) pays an allocation per read; the workaround is a convention callers must know.
- An immortal lazily initialized global: adds initialization order and a thread-safety question to constants, which the language defines as having no storage, and still needs a path for reads that mutate.
- An MIR pass that rewrites `call @const; list.get; drop`: needs a use analysis per call site, and the same new op, because MIR has no way to read static data without a list value.
- Views of non-scalar constants (strings, nested lists, types): not needed for the measured gap. Constants of those types keep the call.

## Risks

- A write through a view would corrupt static data (read-only on Linux, so a fault, not silent). Every write path takes a place or an owned value, and a constant is neither; tests cover append, element set, `var` argument, return, field, nested list and equality.
- A path that treats a borrowed list as owned and does not call `owned` hits the strict copy gate (`implicit copies of a borrow`) at compile time, not at run time.

## Testing

- Lowering fixture: reads emit `list.const.view` and no `call`; `var t = table` emits `clone`.
- Conformance fixture covering the uses above on both backends; `image.ms` and `image-fuzz.ms` for the JPEG tables.
- `bench/perf/image-codecs` before and after.
