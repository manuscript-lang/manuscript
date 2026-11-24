# Scalar index for large non-ASCII strings

Status: proposal, 2026-11-14. Decision requested from Chinmay before any implementation.

## Summary

- Problem: `s[i]`, `get`, `scalar_at`, `slice` and `length()` count Unicode scalars, so each call on a non-ASCII string rescans from byte 0. A loop over every index is quadratic.
- Change under consideration: remember where earlier scans ended so a later call on the same string costs the distance, not the prefix.
- Decision: pick one of the four options below, or do nothing.

## Problem

Measured at b308b8cf (`ms run /tmp/k/na.ms`, 188,890 scalars, 4 vCPU shared VM, one run):

| Loop | Before word-skip | After word-skip |
| --- | ---: | ---: |
| `scalar_at(i)` for every i | 10,864 ms | 5,938 ms |
| `get(i)` for every i | 10,806 ms | 5,521 ms |
| `while i < s.length()` | 2,267 ms | 2,295 ms |

- ASCII strings are O(1): the `STR_ASCII` bit makes index and length direct. Only text with a non-ASCII scalar pays.
- The scan already runs at about 4 bytes per ns (`utf8::advance`) and 11 bytes per ns (`utf8::count`); a faster scan cannot fix an O(n) call made n times.
- Rust `chars().nth(i)` and Python-style scalar indexing over UTF-8 have the same cost shape; Go indexes bytes, so it has no equivalent loop.
- Idiomatic Manuscript already avoids it: `chars()`, `for c in s.chars()`, `index_of` and views are linear. The gap is code that indexes by position.

## Options

1. **Do nothing.** Zero risk. Index loops over large non-ASCII text stay quadratic (about 6 s at 190k scalars, 0.4 ms at 5k).
2. **Scalar count in the string value (O(1) `length()`).** `StrVal.tagged` has 61 length bits but `MAX_BYTES` is 2^30, so 31 bits are spare for a scalar count. Hypothesis, not measured: concat, `build_exact`, `slice` and `replace` know or can sum counts; `0` means unknown. Fixes `length()` loops, not `s[i]`. Touches every constructor of `StrVal` and both backends' inline helpers; a wrong count is a silent wrong answer.
3. **Per-thread block index, validated by an allocator epoch.** One entry per thread: `(ptr, len, epoch, byte offset of every 256th scalar)`, built when scan work on a string passes its length. Valid only while a global counter bumped by every large free, realloc and shrink (`alloc.rs` `free`, `free_large`, `realloc`, `grow_release`) is unchanged. Gives O(1) `s[i]` and `length()` after one O(n) build, for any representation (owned, view, static). Risks: a missed free path returns a stale offset (silent wrong text); a loop that frees large blocks defeats it (falls back to today's cost); one extra relaxed atomic load per large-string call.
4. **Iterator-first, leave indexing slow.** Document `chars()` and views as the way to walk text and add a lint or diagnostic hint on index loops over `String`. No runtime change; users who index still pay.

## Comparison

| | `s[i]` loop | `length()` loop | Risk | Code |
| --- | --- | --- | --- | --- |
| 1 | quadratic | quadratic | none | none |
| 2 | quadratic | O(1) | wrong count if a constructor forgets it | every `StrVal` constructor |
| 3 | O(1) after build | O(1) after build | stale entry if an allocator path misses the epoch | `alloc.rs`, `string.rs`, about 150 lines |
| 4 | quadratic | quadratic | none | diagnostics and docs |

## Recommendation

- Do 3 only if Chinmay wants indexing loops to be fast without changing how users write them. It is the only option that fixes both loops and keeps the two-word layout.
- Do 2 alone if only the `while i < s.length()` idiom matters; it is the smaller, more local change.
- Otherwise 4: the quadratic cases are avoidable with `chars()` today.

## If built (option 3)

- Epoch: one `AtomicU32` in `ms-rt/alloc.rs`, bumped for blocks of at least 4 KiB on free, realloc and shrink; cross-thread frees bump the same counter.
- Entry: thread-local, one string; replaced when another large non-ASCII string crosses the build threshold.
- Used by `scalar_count`, `scalar_offset`, `string_get`, `scalar_at_slow`, `sub_scalars`, `scalar_index` in `ms-rt/string.rs`; the inline fast paths stay unchanged (they only handle ASCII and short strings).
- Tests: model test against `chars()` over random edits; a test that frees and reallocates a same-address same-length string with different text between two indexed reads; a loop benchmark in `bench/perf/string-pass` with a Rust `chars().nth` twin.
- Skeptical review required before merge: challenge every path that can change bytes at a live address (builders, in-place realloc, task arenas).

## Open questions

- Is silent-wrong-text risk acceptable for a speedup on a rare shape (option 3)?
- Is `length()` O(1) alone (option 2) enough?
