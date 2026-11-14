# String micro-benchmarks

One-million-element timings of common `String` operations, each section timed inside the program and checked against a Rust twin (`ops.rs`, `bulk.rs`; same inputs, same checksums).

```sh
ms build bench/perf/string-micro/ops.ms -o /tmp/ops_ms && /tmp/ops_ms
rustc -O -o /tmp/ops_rs bench/perf/string-micro/ops.rs && /tmp/ops_rs
```

Compare numbers only from the same machine; treat them as a profiling guide.

## 2026-11-14

`88287373` plus the change below, Release `ms`, rustc 1.99.1 `-O`, 4 vCPU Xeon VM, ms over Rust, min of 3. Operations within 1.5x of Rust are omitted except the ones changed.

| operation | ms | rust | ratio | note |
|---|---:|---:|---:|---|
| `fields()` of 10.7 MB | 87, then 40 to 57 | 30 | 2.9x, then 1.3 to 1.9x | the native built a Rust `String` per field, then copied each into a runtime string; it now copies once into a list sized up front |
| `trim_chars("w")` per word | 115 | 8 | 14x | open: the stdlib loop reads windows of scalars as lists; a rewrite over `scalar_values()` was no faster, so it needs a native |
| `sorted(a.compare(b))` of 1M words | 550, then 270 to 330 | 337 | 1.6x, then 0.8 to 1.0x | two inline strings (up to 15 bytes) compare as two byte-swapped 128-bit words instead of a `memcmp` call; `a < b` 17 to 10 ms |
| `Float.to_string` | 150 | 110 | 1.3x | not a gap (an earlier 250 was noise) |
| `for c in s.chars(): s += c.length()` | 91 | 9 | 10x | the loop builds a string per non-compared character; comparing against a literal stays a code point (20 ms) |
| `length()` of 8 MB non-ASCII text | 17 per call | 1 | 17x | counts non-continuation bytes eight at a time instead of a validation pass plus a byte filter: 3 ms for both `length()` and `scalar_length()` |
| `for c in s.chars(): if c == "世"` on non-ASCII text | 36 | 10 | 3.6x | open: each non-ASCII scalar decodes twice (value and width, about 97 instructions) |
| `normalize("NFD")` per word | 176 | - | - | no Rust standard-library equivalent |
