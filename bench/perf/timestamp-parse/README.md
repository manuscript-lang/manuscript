# Timestamp parser bounds

The supported grammar has 19 fixed calendar/time bytes, an optional dot and
1–9 fraction digits, and either `Z` or a six-byte numeric offset. Accepted inputs
therefore occupy 20–35 bytes. The length check rejects oversized fractions
without scanning the unbounded digit run (#3282).

The reusable native producer in `rust.rs` times the production Rust parser,
without CLI startup, source compilation or native ABI error construction. It
constructs inputs before timing, puts optimization barriers around each input
and output, and checks the exact timestamp or status on every iteration. It is
an implementation microbenchmark, not a language comparison.

Build the native crate in a clean target directory and link the producer to its
actual artifacts (choose the matching files if the target has several variants):

```sh
cargo build --release --locked -p ms-std-time
rustc --edition=2024 -O -C panic=abort -C force-frame-pointers=yes \
  bench/perf/timestamp-parse/rust.rs -o /tmp/timestamp-parse \
  -L dependency=target/release/deps \
  --extern ms_std_time=$(echo target/release/deps/libms_std_time-*.rlib) \
  --extern ms_rt_abi=$(echo target/release/deps/libms_rt_abi-*.rlib)
/tmp/timestamp-parse valid_z 2000000
/tmp/timestamp-parse valid_max 2000000
/tmp/timestamp-parse bad_frac10 2000000
/tmp/timestamp-parse 1048576 128
```

The first argument selects `valid_z`, `valid_nofrac`, `valid_max`, `short`,
`bad_early`, `bad_date`, `bad_frac10`, `bad_len36`, `range`, `nul`, or a fractional
digit count. The second is the repetition count. Output is the case, repetitions
and elapsed nanoseconds. Divide elapsed time by repetitions. Compare identical
inputs and flags across baseline/candidate builds in alternating order, using
multiple pairs, one CPU where supported, and identical-binary A/A controls.
For extremely cheap rejection paths, use enough repetitions to exceed timer
noise. Do not equate different repetition counts with equal total work.

The public Manuscript benchmarks include the ordinary timestamp from the latest
[whole-suite baseline](../baseline-2026-10-28.md), a maximum-width valid control,
and a 64 KiB invalid fraction. They include native ABI and error-value costs:

```sh
ms bench bench/perf/stdlib/numbers_bench.ms --filter time.parse_timestamp \
  --samples 11 --time 100ms
```

Keep measurements and campaign records outside the repository. Correctness and
error identity belong in the native and called source tests, not timing limits.
