# Append to a string that lives in a slot in place

## Summary

- Problem: `b += f"line {i}\n"` in a loop is quadratic when `b` lives in a slot (a call that can fault is live while it is owned): 200,000 appends took 40 s and `bench/perf/suite/gen.ms` ran over 20 minutes.
- Change: a late `strfuse` run lifts the slot's `take` in front of the concat so the existing fusion grows the string in place; 200,000 appends take 9 ms.
- Decision requested: none; behavior is unchanged.

## Status

Implemented, 2026-11-23.

## Problem

A string variable that must be released if a call faults is held in a slot with a cleanup. `s = s + piece` lowers to `a = load str S; r = concat(a, piece); y = take str S; drop y; put S, r`. `strfuse` grows in place only when its first argument is an owned value that a `drop` follows, so the borrowed `load` copy defeated it and every append copied the whole string: 25k appends 168 ms, 50k 1 s, 100k 8 s, 200k 37 s. A variable held in an SSA value (the `append` guard) was never affected, so the cost appeared only when a faulting call, such as the int-to-string in an f-string, was live.

## Design

`lift_slot_take` rewrites that sequence to `y = take str S; r = concat(y, piece); drop y; put S, r` when nothing between the load and the concat touches the slot and only `drop`s lie between the concat and the old `take`. The fusion then finds an owned first argument followed by its drop. `strfuse` runs again at the start of the late steps, because the early run sees the slot update as a call to the close function, not as `take`/`drop`.

The second run exposed `msrt_bytes_concat_grow` returning a view unchanged when the piece was empty (`Bytes.clone` is `concat(self, self.view(0, 0))`), so the "copy" aliased a freed block; it now copies a view, as it does for a non-empty piece.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_strfuse.c` | lift the slot take | `e2e/accept/string-append-in-slot` |
| `src/compiler/opt/opt_pipeline.c` | run `strfuse` again as the first late step | same |
| `src/runtime/core/bytes.c` | copy a view when the piece is empty | `e2e/accept/return-bytes-view-clone` |

## Alternatives

- Do nothing: natural string building is quadratic whenever a faulting call is live.
- Make the lowering emit `take` and `drop` instead of `load` and the close call: moves the same pattern into lowering, and the early run would still not see the inlined form.
- Wait for the unwinding redesign to remove the slot: it may, but the pattern stays quadratic until then, and a slot can still arise for other owners.

## Measurement

`gen.ms` at scale 1: over 20 minutes before (each of the five 20 MB files took about 6 minutes), 1.5 s after. A loop of f-string appends: 25k 168 ms, 50k 1 s, 100k 8 s, 200k 37 s before; 1, 1, 4 and 9 ms after.

Instruction counts (callgrind, release `ms` from main against this change): `lz` unchanged (688.8M against 689.2M), `strings` -0.5% (1,703.3M against 1,694.0M), the guards within 1% in either direction. A first version of the change cost `strings` +2.7%: the stdlib's own short appends (`pad_start`'s filler, `replace`'s output) were concats of strings small enough to be inline, and an append of an inline receiver went through the owned-block machinery (a part array, a join, a free) for nothing. `msrt_string_append` now hands a receiver that owns no block straight to `msrt_string_concat`, and `msrt_string_append_parts` skips the zeroing and length sum on its copy path.
