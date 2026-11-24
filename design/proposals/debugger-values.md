# Show Manuscript values in debuggers

## Summary

- Problem: a native build carries DWARF line tables and function entries only. `gdb` and `lldb` show an address and a line, never a string, list, record, enum or optional.
- Change: describe every Manuscript type once, from the machine layout, and emit it in both backends. Ship a gdb display helper. Variables come next, once MIR keeps local names.
- Decision requested: none for stage 1 (no language change). Stage 2 touches lowering and the optimizer.

## Status

Stage 1 implemented 2026-11-15. Stage 2 (parameters, locals and inlined frames in Cranelift debug builds: `Func.names`, value labels, `DW_TAG_formal_parameter` and `DW_TAG_variable` location lists, `DW_TAG_inlined_subroutine` frames) implemented 2026-11-15; a reassigned local stays undescribed. LLVM release builds describe types only: variables there cost about 4% of compile time and 0.4% of size for no change in the generated code ([measurement](../../bench/perf/debug-variables-2026-11-15.md)), over the 1% line, so they stay out of release builds. Stage 3 is done.

## Problem

Verified in `crates/ms-clif/src/dwarf.rs` and `crates/ms-mir-llvm/src/llvm_ir.rs`: the compile unit has `emissionKind: LineTablesOnly` and no type DIEs. Values are flattened into scalar leaves (`ms-mir/src/layout.rs`): a `String` is two registers, a list three, an enum a tag plus shared payload slots. So even with a type table a debugger sees only addresses; showing `p` in a frame needs both types and locations.

## Design

1. **One description** (`ms_mir::debug_types`): `String` is `{ptr, tagged}`, `List[T]` is `{ptr: T*, len, cap}`, `T?` is `{present, value}` (or a pointer, or the string layout, as `Layouts` decides), a record has its fields at memory offsets, an enum is `{tag, payload: union of cases}`. A case field spread over separate payload slots shows each leaf. Cyclic types end at the entry already made.
2. **Two renderers**: gimli DIEs in Cranelift; `DIBasicType`/`DICompositeType`/`DIDerivedType` held by the `ms.debug_types` anchor global (a union with one member per type) in the first LLVM unit only.
3. **Display helper** `tools/debugger/manuscript_gdb.py`: decodes the string tag bits, list length, optional and enum case from the struct names and shapes above.

Stage 2 (variables): lowering records a name per MIR value and parameter; the inliner and optimizer keep it; Cranelift value labels and LLVM `dbg.value` give locations per leaf, joined with `DW_OP_piece`. Stage 3 (done with stage 1's follow-up): lldb formatters on the same decoding module; no natvis, since no PDB is emitted and Windows gdb and lldb read the DWARF.

## Evidence

- Cranelift and LLVM builds of a program with a record, an enum, a list and an optional: `gdb -ex 'ptype struct Point'` lists the fields; `print *(struct Shape*)$rsp` with the helper prints `Rect = {w = 2, h = 3}`; `llvm-dwarfdump --verify` reports no errors for both.
- Size: `.debug_info` of the `jsonrt` benchmark grew from 180 to 1818 bytes (Cranelift); the executable did not grow measurably.
- Test: `dwarf_describes_values_for_a_debugger` (names, offsets, verify).

## Alternatives considered

- **Do nothing**: debugging stays at line level; `print` calls are the only way to see a value.
- **A Manuscript-specific debugger or DAP**: dropped earlier (`crates/DESIGN.md`); native tools already exist and need only descriptions.
- **Types only in the helper script**: no `ptype`, no help for lldb or Windows, and the layout is duplicated outside the compiler.
- **Variables first**: needs MIR names across lowering and the optimizer; types are useful alone and are the shared base.

## Review

An independent skeptical review (2026-11-15) found a wrong offset for a record or optional whose fields sit after an unaligned leaf (fixed: a field is shown whole only when its leaves keep their relative offsets, else per leaf; pinned by the `inner.1` assertion), a helper that matched `List[Int]?` as a list and matched by name alone (fixed: shape is checked too), and that types without variables are only partly useful (agreed: stage 2 follows; types alone already serve `ptype` and addressable values).

## Risks

- A layout change must change `debug_types` with it; it reads `Layouts`, so it follows by construction, and the test pins the shapes.
- `LineTablesOnly` still emits retained types in the bundled LLVM; a different LLVM could drop them (the dwarfdump check in the LLVM gate would catch it).
