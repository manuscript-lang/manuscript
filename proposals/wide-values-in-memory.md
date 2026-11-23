# Values of many leaves live in stack cells, not registers

## Summary

- Problem: the emitter spreads every value over one SSA register per leaf, so a 66-leaf record (the YAML parser's `Flow`) is 66 spilled registers wherever it is live, plus a 520-byte argument copy per call.
- Change: in Debug builds a value of more than `wide_leaves` leaves lives in a stack cell; each instruction loads only the leaves it reads; calls pass the cell's address; cells that are never live together share storage.
- Decision requested: none (no language change; Release code is unchanged).

## Status

Implemented 2026-11-23. A module with a size tier (`optnone`) is emitted again without held values, since llc -O0 gives each load a slot. Chinmay: "2.7KB is HUGE, what are we wasting this much stack on? these should be in hundreds of bytes" and "make sure you're not special casing this". The rule below is a leaf count on any type.

## Problem

Debug frames (`ms build --build-type Debug`, `llc -O2`) of the standard-library parsers, largest frame of any function:

| Program | Before | After |
| --- | --- | --- |
| `@std/data/toml.ms` parse | 1144 B (`materialize`) | 856 B (`string_value`) |
| `@std/data/yaml.ms` parse | 3816 B (`flow_value`) | 3240 B (`flow_value`) |

- `flow_value` holds `Flow` (66 leaves, 520 bytes) as SSA values: phis at every block parameter, a spill slot per leaf, a 520-byte `%X` copy for each call that takes one.
- Registers are the wrong home for a value that is read a few leaves at a time and copied whole.

## Design

- A value is *held* when its type has more than `wide_leaves` leaves (default 4, `MS_WIDE_LEAVES` overrides, 0 turns it off) and something reads it. The test is `leaves.len > wide_leaves`, nothing else.
- Where a held value is made, its leaves are stored to its cell. An instruction that reads it gets one `load volatile` per leaf it names, just before itself, under a name of its own; `volatile` keeps `opt` from merging the loads into long-lived registers again.
- A block parameter that is held has a cell and no phi. Each edge copies the argument's cell (`llvm.memcpy`) into it; a conditional edge goes through a block of its own so only the taken edge copies. An argument that is a parameter of the target (a swap around a loop) is copied leaf by leaf from loads taken before any copy.
- A held argument of a call is passed by the address of its cell, a held result is written to its cell by the callee, and a parameter that arrives by address is read from there.
- Cells and `slot`s share storage when they are never live together (`mir_cell_conflicts`: block liveness plus a backwards walk per block; a callee's result conflicts with its arguments, any other operation may replace its operand). Cells are given to LLVM through an empty `asm`, so `opt` does not promote them back to registers.
- Release builds keep registers: `wide_leaves` is 0 unless the build is Debug.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/emit/emit_wide.c` | which values are held, per-instruction loads, edge copies | e2e fixtures at `MS_WIDE_LEAVES=4` and the default |
| `src/compiler/emit/emit_call.c`, `emit_term.c`, `emit_func.c` | pass cells, edge blocks, per-instruction text | same |
| `src/compiler/mir/mir_slot_scope.c` | `mir_cell_conflicts` replaces the one-block slot scope | same |
| `src/cli/pipeline.c`, `backend.c` | `wide_leaves` option | `ms build` Debug |

## Alternatives

- Do nothing: yaml and toml frames stay at 3.8 KB and 1.1 KB.
- Box big records in the stdlib: rejected by Chinmay (no stdlib workaround; the compiler should do it for every type).
- Hull ranges for cell sharing: 9 cells of 520 bytes in `flow_value`, frames doubled; exact conflicts need 2.
- Non-volatile loads: `opt` hoisted them, 1273 loads lived across blocks again.

## Measurements

Debug, `llc -O2`, x86-64; largest frame and sum of the frames of all Manuscript functions (`mf.sh`: `sub rsp` of each function):

| Threshold (`MS_WIDE_LEAVES`) | toml largest / sum | yaml largest / sum |
| --- | --- | --- |
| 0 (off) | 1144 / 23224 | 3816 / 60032 |
| 3 to 6 | 856 / 20776 | 3240 / 61696 |
| 8 | 984 / 21568 | 3304 / 62648 |
| 12 | 1160 / 24400 | not measured |

Between 3 and 6 nothing changes, so the default is 4 (2 fails: the emitter names a two-leaf value `%v<N>`). The change does not reach "hundreds of bytes" for `flow_value`: it still holds two 520 B `Flow` cells, a 400 B `Context` copy and a 200 B copy. The next lever is views of the fields of a held record, so `type.get` stops copying whole sub-records.
