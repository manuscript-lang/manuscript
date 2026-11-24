# Small strings inline in the two-word String

Status: implemented, 2026-10-23, after a skeptical review and its attribution experiment. Follows `two-word-string.md` (shipped in #1089). Result: toml median 2.09 s against 2.04 s for the refcounted build and 2.37 s before this change.

It replaced two follow-ups that were measured and dropped: returning `String` in registers (about 0.3% on the parsers suite, for 145 runtime signatures and a Windows adapter) and slice views (no hot use in any benchmark, and a new escape risk).

## Problem

A `String` has a single owner. Copying an owned string calls `msrt_str_dup`, which mallocs and copies, and dropping it calls `msrt_str_free`. Under the old reference count, a copy was an increment. Programs that keep many short keys and values pay a malloc and a free for each copy, plus cold-memory traffic:

- `toml.parse` of 2,000 tables, run 200 times: 10.8M string duplications, of which **10,794,000 are 15 bytes or shorter** (200 are longer), and 13.2M allocations of short strings. Wall time is 2.42 s, against 2.00 s for the refcounted build, while the instruction counts are about equal (15.9G against 16.0G). The difference is malloc/free and cache misses (D1 misses +15%, I1 misses +60%).
- The other workloads have the same shape. Short duplications against all duplications: inventory 315K of 315K, ledger 863K of 980K, csv 676K of 676K, parsers 558K of 564K. Short allocations against all allocations: ledger 1.80M of 2.60M, inventory 1.44M of 2.17M.
- With moves at last use and in-place append landed, toml still takes a median of 2.57 s against 2.13 s for the refcounted build (11 interleaved runs pinned to one core). In the parsers suite, yaml, html and the ledger are 3–6% behind.
- **Attribution experiment** (asked for in review). A throwaway build where generated string copies alias and nothing is freed brings toml to 2.18 s, which is within noise of the refcounted build. So the gap is the copies and frees themselves, not code layout. Inline strings remove 99.99% of those copies in toml.

## Change

A string of at most 15 bytes stores its bytes in the value itself.

- **Tag.** The top two bits of `tagged` are `00` owned, `01` inline, `10` static, `11` view. For an inline string, bits 56–59 hold the length, and the bytes take the 15 bytes of the value starting at its address (little-endian: the whole `ptr` word, then the low 7 bytes of `tagged`).
- **Drop.** A string is freed only when it is owned: `tagged < 1 << 62` (unsigned). That is one compare, as it is today.
- **Copy.** Static and inline strings copy bitwise (`tag` is 1 or 2). Owned strings and views are duplicated; a duplicate of 15 bytes or fewer comes out inline, so it never allocates.
- **Presence of `Optional[String]`.** None stays `{ptr: 0, tagged: STR_STATIC}`. An inline string can have a zero `ptr` word (for example `""` or a leading run of NULs), so presence is `(ptr | (tagged ^ STR_STATIC)) != 0`, not `ptr != 0`.
- **Length.** `len()` is `(tagged >> 56) & 15` for an inline string, and `tagged & STR_LEN_MASK` otherwise. Generated code computes it with a select.
- **Bytes.** The runtime reads strings through `*const StrVal`, so the data pointer is `if inline { s as *const u8 } else { s.ptr }` (`StrVal::data(&self)`). Generated code that reads bytes (`str.byte`, literal compare, builder append) spills the two words when the string is inline.
- **Producers.** `from_bytes`, `owned_copy` (dup), concatenation, `split` pieces, `char_at`, the ASCII character table and substrings return inline values when they fit. A view of an inline source is an inline copy, because the source's address may be a temporary.
- **Unchanged.** Static literals, the MIR, the checker, and the language.

## Alternatives

- **Do nothing.** toml, yaml and the ledger stay 3–20% slower than the refcounted build, and every short map key costs a malloc per copy.
- **Reference-count again for owned strings.** This reverses the direction the owner chose ("I want to get rid of ref counting").
- **Intern short strings.** We prototyped this before and it lost: a lookup per string, with no gain on these workloads.
- **More copy elimination.** The remaining copies are real: a key stored in a map, and a value kept while the source table lives on (`materialize` in toml). Only a cheaper copy helps them.

## Cost and risk

Review counted about 330 `.ptr` reads in `ms-rt` and the `ms-std-*` crates. Most of them are lists and objects, but each string read becomes `data()`, and `msrt_str_dup` and `msrt_str_free` change signature. A missed read would be a wrong-bytes bug on short strings, so the conformance corpus, the e2e fixtures and the leak check all cover it, and one runtime test checks every string native on inline input. Generated code gains a select on each length read and on each byte read. The views (`split_view`, map `keys_view`) must copy inline sources instead of pointing into them.

## Measure of success

toml and yaml reach parity with the refcounted build or beat it, and no workload in `ab.sh` regresses by more than noise.
