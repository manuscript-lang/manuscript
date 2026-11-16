# Regex search over a large text

`main.ms` compiles two patterns and, over one 15 MB text, runs `find_all`, `find_all_spans`
and `replace_all` with `func\s+\w+\(` and `find_all` with `[A-Za-z_]+[0-9]+`. `main.rs` is the same
work with the `regex` crate (features `std`, `unicode-perl`, `unicode-case`, `perf`) and `main.go`
with Go's `regexp`; all three print `15900 15900 15082008 181642`.

Input: `cat $(find /usr/local/go/src -name '*.go' | head -1500) | head -c 40000000 >
/tmp/regex-search-input.txt` (15344672 bytes). Build `ms build bench/perf/regex-search/main.ms`,
`go build main.go`, and the Rust file in a scratch crate with `cargo build --release`.

## 2026-11-16, `main` 724c8dda, Linux x86-64, wall time of 3 runs

`ms-std-regex` built `regex` with `default-features = false` and without `std`, so
`aho-corasick` ran its full-DFA fallback (no Teddy SIMD prefilter): 30318 calls at about
14000 instructions, 40% of 1035M total, against 442M for the Rust program. Adding `std` and
`perf-cache` to the crate's `regex` features gives it the same prefilter.

| Program | Wall time |
| --- | --- |
| Before (no `std`) | 180 to 190 ms |
| After | 104 to 112 ms |
| Rust `regex` | 94 ms |
| Go `regexp` | 900 to 950 ms |

The remaining difference to Rust is `decode_utf8` of the input and the `String` copy per match.
