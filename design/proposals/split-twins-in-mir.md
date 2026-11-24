# Split twins in MIR: a split read in place makes no heap list

## Summary

- Problem: `line.split(" ")` builds a heap list on every call, and the result is usually read in place (`f[3]`, `f.length()`) or only for element 0. The runtime has twins that avoid the list (`msrt_string_split_first`, `msrt_string_split_view_into`, written for the Rust compiler), but the C compiler never calls them. `split_view` is 62% of `logstats`' instructions, 32% of `dedupe`'s and 34% of `grep`'s.
- Change: the signature of `msrt_string_split_view` declares `@twin=split_view`; a new MIR pass `splitview` rewrites each such call whose list is only read and dropped. Only element 0 read after the call: `split_first`, no list. Any other in-place reads: `split_view_into` with a frame buffer of eight strings (the runtime falls back to the heap list for a longer text or more pieces). `split_view_into` also scans with a word-wise byte search and builds short pieces inline.
- Decision requested: none; behavior is unchanged.

## Status

Implemented, 2026-11-23.

## Problem

`String.split` on a name or field lowers to `msrt_string_split_view`, whose list allocates, grows, and is freed per call: 450 instructions for a line of two fields, 810 for six. The Rust lowering picked the twins from statement analyses (`first_for`, `view_for`); the C lowering kept only the view form, so every `f := line.split(" ")` and `line.split(" ")[0]` paid for a list the function never let escape.

## Design

- Sig attribute `@twin=<family>` (parsed by `cmake/EmbedNativeSigs.cmake`, carried on `MirExtern.twin`). No symbol name is read by the pass; the twins' names are written once in `opt_splitview.c`.
- The pass classifies each use of the call's list. `drop`, `list.len`, `list.get[.nn|.u]`, `list.addr[.u]` keep it local; any other use (a call argument, a store, a block argument, a return, `list.take`, `list.push`, `list.cap`) leaves the call as it is.
- First piece: the only reads are `list.get` of the constant 0 in the call's block with nothing that writes, faults, or allocates between. The call becomes `split_first`, those reads become its result, and the list's drops drop that result.
- Frame: `slot SplitFrame` (eight strings) before the call; the call becomes `split_view_into(text, sep, slot)`. The list it returns has capacity 0 and owns nothing when it fits, so the drops stay as they are.
- `split_view_into`: `ms_find_byte` (words for the first bytes, then memchr) replaces the byte loop; `make_piece` builds a short piece with `ms_string_make_inline` (the old `make_inline`, now in `base/string.h`).

## Evidence (callgrind instructions, base `main` vs this change)

| Program | Before | After | Change |
| --- | --- | --- | --- |
| logstats | 913.8M | 600.5M | -34.3% |
| dedupe | 1789.4M | 1346.6M | -24.7% |
| grep | 166.8M | 164.0M | -1.7% |

The rest of the suite is in the PR.

## Alternatives

- Do nothing: the five line-parsing programs stay 1.4 to 1.8x checked C, mostly in the split.
- Select the twin in lowering by statement analysis, as the Rust compiler did: needs a second dataflow over the HIR and misses splits that appear after inlining; the MIR pass sees the uses directly.
- A lazy iterator for `for piece in text.split(..)` is the third twin (`msrt_string_split_iter`); it changes the loop shape, so it is a separate change.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/runtime/core/string_split.{c,h}` | `@twin` on the sig; word-wise search and inline short pieces in `split_view_into` | `e2e/accept/split-twins-first-and-frame` |
| `cmake/EmbedNativeSigs.cmake`, `native_sigs.h`, `lower_native*.c`, `mir.h` | the twin attribute reaches `MirExtern.twin` | same |
| `src/compiler/opt/opt_splitview.c`, `opt_pipeline.c` | the pass, after `inline` | same |
| `src/base/{string,search}.{c,h}` | `ms_string_make_inline`, `ms_find_byte` | `ctest` |
