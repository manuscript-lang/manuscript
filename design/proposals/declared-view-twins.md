# Declared view twins: one rule for borrowing native results

## Summary

- Problem: lowering picks the borrowing form of `split` by the method name (`"split"` in `native/method.rs`, `expr.rs`, `stmt.rs`) and by a parameter named `buf` of type `*mut SplitBuf` (`rtcall.rs`). The next lent native would add a fourth copy of each.
- Change: a runtime function declares its borrowing twin in the `// ms:` comment above it (`view_of=`, `shared_view_of=`, `first_of=`, `iter_of=`). Lowering reads the declaration for any native; no method name appears. The frame buffer is one generic type, `FrameBuf<T, N>`, picked by type.
- Decision requested: none (no language or user-visible change); stage 2 below needs a go-ahead on scope.

## Status

Stages 1 and 2 implemented, `6e26a40c`: conformance 4036 pass, guard counts equal to main (`guard-splitbuf` 78.05M vs 78.05M, `guard-splitfirst` 39.15M vs 39.15M). Stage 2 is a plan.

## Problem

- Four name or shape checks keyed on `split`: `split_view_for`, `split_iter_for`, `split_first_for` plus the literal-`0` index test (`first_of_split`, `expr.rs`), and the `SplitBuf` check. `Map.keys`, `Map.values` and `List.slice` already had their own copy (`keys_view_symbol`, an arm per name), so each lent native costs one more arm in two places.
- A `ViewResult` extern role came from a list of six symbol names in `rtcall.rs`.

## Design

- Flags on the twin, read from `rt_symbols.txt` (`cargo xtask symbols`): `view_of=<base>` (the result borrows the receiver), `shared_view_of=<base>` (same, but the list shares the receiver's element storage, so only for elements that own nothing), `first_of=<base>` (element 0 as a single value), `iter_of=<base>` (an iterator object). `<base>` is the symbol the method lowers to today (`msrt_string_split`).
- Lowering asks `rt_twin(base, kind)`. The checker's `BorrowedRead` fact still decides when a result may borrow; the declaration only says how.
- `ExternRole::ViewResult` is derived from the twin flags, so the name list goes.
- Statement analyses (`let parts = x.m(..)` read only in place; `let` then `for`) and the `[0]` test ask the same question of the resolved method, not its spelling. `keys_view_for` and `split_view_for` merge into `view_for`.
- `*mut FrameBuf<StrVal, 8>` in a runtime signature makes lowering pass a frame slot, any callee, any element count. `SplitBuf` goes.
- A set shares its map's entry points but not their views, so a set receiver never takes a twin.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt`, `ms-rt-abi` | flags on six functions; `FrameBuf<T, N>` | `cargo test -p ms-rt` |
| `crates/xtask`, `ms-lower/build.rs` | accept and carry the twin flags | `cargo xtask symbols --check` |
| `ms-lower` | `rt_twin`, one selection block, no name checks | conformance fixtures `split-first-piece`, `split-in-frame`, `lent-collection-views` |
| `bench/perf` | guards `splitfirst`, `splitbuf` | `make perf-counts` |

## Alternatives

- Do nothing: each new lent native adds name checks in three files.
- A library first-piece API (`text.first_piece(sep)`): changes user code instead of fixing lowering, and `split(..)[0]` stays slow for everyone who writes it.
- A lazy list type: a new language-level type for a lowering detail.

## Stages

1. This PR: twins declared and read, name checks deleted; guard counts equal or better.
2. Group the per-call fast paths (below); counts identical.

## Per-call fast paths (stage 2, implemented in the stacked PR)

- Review of the group: `inline_probe` (`rtinline.rs`: `read_word`, `index_of_byte`, `view`, `bytes_view`, map probes), `inline_str` (`rtstr.rs`: `parse_int`, `contains`, `compare`, `starts_with`, `ends_with`, `scalar_at`, `scalar_step`) and `opt/appendfast.rs` each repeated the same lines: build an internal `inline(always)` function, look it up by `HelperKey`, cache it. `eq_lit` is a MIR operation planned once in MIR (#4296), not a generated function, so it stays.
- Change: `FuncBuilder::fast_path` (`ms-mir`) is the one constructor, used by all seven helpers and by `appendfast`; `fast_path_cached`/`fast_path_add` are the one cache; `str_fast` is the table for string symbols and `inline_probe` the only dispatch (the second `inline_str` match is gone).
- Evidence: generated code is unchanged (`guard-strcmp`, `guard-append`, `guard-findshort`, `guard-splitbuf` and `strings` counts identical before and after); about 60 lines fewer.
- Not done: moving the probes into the MIR pipeline as a pass. The lowering decides by symbol and operand shape (a literal needle, an operand count), which the MIR already has, but the move changes where those decisions run and needs its own measurement.
