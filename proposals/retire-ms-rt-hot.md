# Retire `ms-rt-hot`: the compiler emits the fast paths

## Status

Requested by Chinmay (2026-11-12): "ideally we don't have this hot crate and just do it in Manuscript", then "make the compiler emit fast code instead". Draft; not implemented. PR #3730 (more `ms-rt-hot` functions) is held as the baseline. This reverses the wiki note of the same day that says to keep moving fast paths into `ms-rt-hot`; the wiki page changes when group A lands.

Constraint (Chinmay, 2026-11-12): no language or grammar change. Everything below is lowering, MIR, stdlib `.ms` in existing syntax and compiler-side hints; a source-level need in group C is an open question for Chinmay, not an assumption.

## Summary

- Problem: LLVM sees the runtime only as opaque calls, except the 45 pure functions of `ms-rt-hot`, which a separate crate, an xtask IR step and an `llvm-link` step inline. Each new fast path means a Rust function plus a `*_slow` twin.
- Change: have `ms-lower` emit each fast case itself (MIR or generated IR), calling the existing `ms-rt` function only for the rare case. When the last function is gone, delete `ms-rt-hot`, the xtask IR step and the `llvm-link` step.
- Decision requested: approve the order below, starting with group A.

## Problem

- Whole-runtime IR failed (duplicated statics, minutes of `opt`: `architecture/runtime-lto-proposal.md`), so inlining goes through the 1290-line `ms-rt-hot` crate (with #3730) (verified: `crates/ms-rt-hot/src/lib.rs`).
- Two codepaths hold one behavior: the compiler lowers `list.get` inline already (`native/list.rs` `list_get_or`), while `first`, `last`, `Bytes.get` and the compares are runtime calls that `ms-rt-hot` then inlines. #3730 measured `first()`+`last()` 17.7 ms to 10.7 ms and `index_of_byte` 8.75 ms to 5.44 ms from inlining alone.
- Rules for what goes where (`crates/DESIGN.md`) and the signature traps (`u8` against `i64` returns silently kept calls) exist only because the inlining is indirect.

## Design

Each hot function moves to the group that fits it; every step keeps behavior and keeps the `ms-rt` body as the slow path.

- **A. One MIR operation or a few: emitted inline.** List `first`/`last`/`at`, `Bytes.get`/`view`/`starts_with`/`ends_with`, `Int`/`UInt64`/`Float` compare, `UInt64` div/rem/to_float, `String.length`/`byte_length`/`is_empty`, ASCII `scalar_at`/`char_width`/`scalar_at_byte`. Lowering emits the test (bounds, ASCII flag or byte below `0x80`, zero divisor) and the fast load, and the existing runtime symbol is the slow branch. About 20 of the 45 functions; the rest (`strbuilder_append`, string `eq`/`view`/`starts_with`/`ends_with`/`scalar_length`, `list_get`) go to B or stay.
- **B. Short scans and hashes: `.ms` stdlib or MIR loops.** `index_of`, `contains`, `find_short`, `memchr_short`, `bytes_eq`, `compare`, `hash_bytes`, `hash_int`, `parse_int`, `Bytes.index_of_byte` near scan. The native-fallbacks thread owns find and equality and has shown blocked byte loops in `.ms` match `memcmp` (732 against 765 us per 20 MB) and come within 2.6x of `memchr`; this proposal adopts its results and does not redo that work.
- **C. Layout-specific map probes.** `get_ptr`/`contains`/`get` for `Int` and `String` keys with word values, `Set[Int]` `contains`, `length`, `slot_count`, `entry_ptrs`. Lowering already picks the symbol from the types (`word_map_symbol`, `rtcall.rs:292`) and so knows the slot stride and key kind. It can emit the probe loop as a generated function per (key kind, value size), once per module, as ordinary IR. This is the hardest group; it needs raw loads at a stride, which MIR must express (open question).
- **D. Delete.** Remove `crates/ms-rt-hot`, `xtask`'s `ms_rt_hot.ll` step, `ms-clif`'s `llvm-link` of it and `MS_RT_HOT`, and fold `bytes`/`equal`/`hash` helpers `ms-rt` still needs into `ms-rt`.

## Avoiding per-method cases in `ms-lower`

Chinmay asked for a design where lowering has no special cases. Verified: MIR already has an inliner (`ms-mir/src/opt/inline.rs`: `InlineHint::Always`, `Auto` up to 60 instructions) and raw-access operations (`ListAddr`, `PtrField`, `Load`, `Store` in `ir.rs:295`).

- Write each fast path as `.ms` in the stdlib file that declares the method: the fast case inline, the rare case a call to the existing native as an `extern fn`. `ms-lower` then has no entry for it.
- Mark such functions for `InlineHint::Always` (a stdlib-only marker, or `Auto` where small), so the inliner does what the `ms-rt-hot` bitcode link does today, on both backends.
- Map probes need the strided load and a branch hint; add them once as `@std`-only primitives, and select the layout by generics rather than `word_map_symbol`.

Open: whether `List[T].first()` in `.ms` can express the owned-element copy for non-word `T` without a `Clonable` bound; if not, the native stays the slow case for those types.

## Components

`ms-lower` (`native/list.rs`, `native.rs`, `rtcall.rs`, `mapset.rs`, `expr.rs`, `fuse.rs`), possibly `ms-mir` (raw strided load), `stdlib/*.ms`, `ms-rt` (slow twins stay, hot re-exports go), `ms-rt-hot`, `xtask`, `ms-clif`, `rt_symbols.txt`, `crates/DESIGN.md` and the wiki page.

## Evidence required per step

- Callgrind instructions and wall time before and after on `bench/perf/rt-hot-moves` and the engineering suite (`wordfreq`, `logstats`, `grep`), against the latest dated baseline.
- `opt` plus `llc` time for hello world and a map-heavy program: inline probe loops grow every module, which is why a hot crate was linked only `--only-needed`.
- Debug (Cranelift) builds must keep the same behavior; they never had the hot IR, so group A and C emit code there too.
- `make conform` and `make drift-check` (LLVM against Cranelift).

## Alternatives

- Do nothing: keep adding to `ms-rt-hot`; every addition needs a twin and a signature check.
- Whole-runtime IR: rejected (above).
- Merge `ms-rt-hot` into `ms-rt`: loses the purity boundary and still leaves calls opaque.
- Write everything in `.ms` stdlib: fine for group B, but A and C need layout knowledge that only the compiler has.

## Open questions

- Does MIR have a strided raw load and compare, or does group C need a new operation? (Hypothesis: it needs one.)
- Is `opt` time acceptable for emitting a probe loop per map type instead of linking one shared copy? Measure before group C.

## Pilot result (2026-11-12)

`List.first`/`last` over a 5M-call loop: 17.8 ms as a runtime call, 10.8 ms through `ms-rt-hot`, 2.6 ms as an inline Rust special case in `ms-lower` (merged in #3730), 2.3 ms as a stdlib `.ms` body. Chinmay prefers `.ms` over more Rust, but the `.ms` body is not a drop-in: the checker treats these natives as borrows of the receiver, a `.ms` body returns an owned value, two `ms-check` tests fail and boxed optionals fail MIR verification. So group A needs one prerequisite first: a stdlib function that returns part of its receiver borrows like a native (`proposals/borrowing-stdlib-bodies.md`, implemented): `first`/`last` are now plain `.ms`, 2.3 to 2.6 ms.

## Skeptical review (2026-11-12) and what changed

- No measurement yet shows compiler-emitted code beating the hot crate; #3730 only shows inlining helps. So A is a pilot first: `first`/`last` (done, in `.ms`) and `Bytes.index_of_byte`, compared against #3730's numbers, and only a win or tie continues.
- `first`, `last`, `at` have no MIR op today (`list_get_or` composes `list_get`, `list_len`, `select`); the pilot builds them from those and counts the new ops needed on both backends.
- Deleting the crate duplicates or re-homes the probe, hash and equal code `ms-rt` shares (`DESIGN.md:54`); group C must show that before D.
- `runtime-lto-proposal.md` preferred emitting directly (its B) and the project shipped the hot crate instead; the pilot is the test of why B lost. Per-type probe loops lose `--only-needed` sharing, so `opt`/`llc` time is measured at each step, not only before C.

## Order

A (one PR, measured), then B with the native-fallbacks thread, then C, then D. Fewer, larger PRs: A and D bracket the series.
