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

No change needed. Min of 3, ms, same VM: `builder_mixed` 33 (Rust 26 to 39), `concat3` 23 (Rust 59), `interp_strings` 41 (Rust 123), `plus_equals` 16 (Rust 18), `int_hex` 30 (Rust 40). The remaining `trim_chars` gap (15 vs 7) is an owned result against Rust's borrowed slice; closing it needs the checker's borrowed-result rule for `trim` extended to `trim_chars`, which is keyed on the method name today (`ms-lower/src/call.rs`), so it waits for the general borrowed-results design (`proposals/borrowed-results.md`).
