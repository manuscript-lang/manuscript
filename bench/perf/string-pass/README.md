# String pass

Twenty-two realistic string workloads over one million words and paths each (word counts with string keys, character and byte scans, ASCII and non-ASCII text, affix tests, search, split, replace, case mapping, concatenation, interpolation, builders, equality, number formatting), timed inside the program, each with the same algorithm in a Rust twin (`main.rs`, same inputs).

```sh
ms build bench/perf/string-pass/main.ms -o /tmp/sp_ms && /tmp/sp_ms
rustc -O -o /tmp/sp_rs bench/perf/string-pass/main.rs && /tmp/sp_rs
```

Rust's `HashMap` uses SipHash, so the `freq_*` and `lookup_long` rows are not a fair hash-speed comparison; the others are. Compare numbers only from the same machine; treat them as a profiling guide.

## 2026-11-14

`27549ff2` plus this change, Release `ms`, rustc 1.99.1 `-O`, 4 vCPU Xeon VM, min of 5, milliseconds.

| operation | before | after | rust | change |
|---|---:|---:|---:|---|
| `s.starts_with(p)` per word (`string-micro` `starts_with`) | 15 | 3 | 5 | inline MIR for affixes up to 16 bytes: two overlapping loads, no `memcmp` call (callgrind: 58 to 6 instructions per call) |
| `starts_with` and `ends_with` on 55-byte paths | 11 | 7 | 10 | same |
| `lower()` of a 55-byte path | 40 | 22 | 26 | ASCII text is copied once into its result and mapped there; it went through a `Vec`, a second copy and a second ASCII scan |
| `reverse()` of a short word (`string-micro`) | 66 | 14 | 52 | ASCII and non-ASCII text are written backwards into the result, no `Vec` |
| `upper()` of a short word | 29 | 23 | 27 | as `lower()` |
| `Float.to_string` | 167 | 144 | 111 | the digits were rendered into a `Vec` and copied again; they are now rendered into a stack buffer |
| `parse_float` of the printed text | 218 | 186 | 135 | a literal with at most 19 digits and a power of ten within 22 is one exact multiplication or division (Clinger), validated in the same pass; the rest takes the general parser as before |

## 2026-11-14, round 2

`a8deb279` plus this change, same machine and method, milliseconds.

| operation | before | after | rust | change |
|---|---:|---:|---:|---|
| `Float.to_string` of 1M floats | 167 | 61 | 111 | Schubfach shortest digits (`float_digits.rs`, a 617-entry table from `tools/float-table.ms`) instead of formatting through `{:e}` and reparsing; callgrind 2,200 to 800 instructions per call including setup. Checked bit for bit against the standard formatter on 60M random patterns, every binary exponent and the edges of each binade |
| `parse_float` of the printed text | 218 | 102 | 135 | the faster digits plus the round-1 exact path |
| `to_fixed(2)` of 1M floats | 153 | 47 | 151 | an exact integer path for values under 2^53 with up to 15 digits: one 128-bit product, a shift, and the remainder decides the tie (half to even); other values use the standard formatter |
| `fields()` of 10.7 MB (`string-micro` `fields`) | 41 | 24 | 24 | one byte loop with a class table instead of `split_whitespace` and a copy per field |
| `trim_chars("w")` per word | 21 | 15 | 7 | ASCII set members tested from two 64-bit masks; no per-call UTF-8 validation of both strings |

## Round 3 check (2026-11-14): builders, concatenation, interpolation

No change needed. Min of 3, ms, same VM: `builder_mixed` 33 (Rust 26 to 39), `concat3` 23 (Rust 59), `interp_strings` 41 (Rust 123), `plus_equals` 16 (Rust 18), `int_hex` 30 (Rust 40). The remaining `trim_chars` gap (15 vs 7) is an owned result against Rust's borrowed slice; closing it needs the checker's borrowed-result rule for `trim` extended to `trim_chars`, which is keyed on the method name today (`ms-lower/src/call.rs`), so it waits for the general borrowed-results design (`design/proposals/borrowed-results.md`).

## 2026-11-15: byte-offset positions

Positions in `String` are byte offsets (`design/proposals/byte-offset-strings.md`). Same VM and method, min of 5, milliseconds, Release `ms`, rustc `-O`. Revision: this change on top of `main` after round 3.

| operation | before | after | rust | change |
|---|---:|---:|---:|---|
| `utf8_offset_walk`: `scalar_at(offset)` over every scalar of 11.5 MB of non-ASCII text (new row) | quadratic: `scalar_at(i)` and `get(i)` over every index of a 189k-scalar text took 5,938 and 5,521 ms | 19 | 11 | an offset is O(1); there is no scalar index to scan for. Each non-ASCII scalar still calls the runtime decoder (inline only for ASCII), which is the remaining gap |
| `utf8_len_index_count` | 6 | 6 | 12 | `scalar_length` and `index_of` unchanged; the match position is now a byte offset |
| `chars_scan_utf8` | 14 | 14 | 8 | unchanged |

`length()` is now a field read (it counted scalars before: O(n) on text that was not flagged ASCII). `utf8_case_reverse` (150 vs 89) is unchanged by this change and still open.

## 2026-11-15: inline scalar decode

`scalar_at` decodes two-, three- and four-byte scalars in the generated MIR (a string is valid UTF-8, so the lead byte fixes the length and the continuation bytes are in bounds); only a continuation byte or an offset outside the text calls the runtime. Same VM and method, min of 5, milliseconds.

| operation | before | after | rust | change |
|---|---:|---:|---:|---|
| `utf8_offset_walk` | 19 | 12 | 11 | no runtime call per non-ASCII scalar |

## 2026-11-15: non-ASCII case mapping, reverse and scalar walks

Same VM and method, min of 5, milliseconds, 11.7 MB of text with 2-byte scalars.

| operation | before | after | rust | change |
|---|---:|---:|---:|---|
| `reverse()` | 50 | 20 | 34 | each scalar's bytes move whole; no decode and encode |
| `upper()` | 71 | 50 | 53 | scalars map straight into the result; no `String`, UTF-8 check or copy. Text that grows (`ß`), or lowercase text with a final-sigma context, takes the `str` path |
| `lower()` | 74 | 50 | 60 | as `upper()` |
| `chars_scan_utf8` | 14 | 10 | 8 | the scalar step of `for c in text.chars()` and `scalar_values()` decodes inline instead of calling the runtime |
| `utf8_case_reverse` | 133 | 75 | 81 | the two above |

Also in this change: `capitalize()` of text that starts with an ASCII letter is one ASCII uppercase and a concat (54 to 30 ms for 1M words, Rust 39); it went through the general titlecase path. The `bytes_scan` row (13 vs 7) compared a copy (`as_bytes()` copies) with Rust's borrowed slice; the Rust twin now copies too. Round 4 sweep of other operations over 1M words and 11 MB texts (`lines`, `split`, `replace`, `count`, `contains`, `index_of`, `pad`, `chars`, `reverse`, `upper`, `compare`) found none over 1.2x of Rust except `lines` (17 vs 10, 1M owned strings in a list against a lazy iterator) and `contains_short` (21 vs 15), both unchanged.

Follow-up check: `lines()` of 1M lines is 17 ms against 15 to 21 ms for Rust's `lines().collect::<Vec<&str>>()` (the 10 ms figure counted lazily without building a list), so it is at parity. `contains` of a six-byte literal in a 40-byte path stays at about 21 against 15: callgrind shows 225 instructions per call (the search is 170 of them); a two-byte SWAR filter over eight positions per step (first and last needle byte) measured 177 for the search itself, no better than the existing memchr-then-compare, so it was not kept.
