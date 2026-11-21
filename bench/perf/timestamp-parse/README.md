# Timestamp parser bounds

The supported grammar has 19 fixed calendar/time bytes, an optional dot and
1–9 fraction digits, and either `Z` or a six-byte numeric offset. Accepted inputs
therefore occupy 20–35 bytes. The length check rejects oversized fractions
without scanning the unbounded digit run (#3282).

The parser is C (`src/runtime/std/time_text.c`) and its limits are checked by `src/runtime/tests/std_time.c`; the Rust
producer that timed the old parser went away with its crate. Time the public Manuscript benchmarks below instead.

The public Manuscript benchmarks include the ordinary timestamp from the latest
[whole-suite baseline](../baseline-2026-10-28.md), a maximum-width valid control,
and a 64 KiB invalid fraction. They include native ABI and error-value costs:

```sh
ms bench bench/perf/stdlib/numbers_bench.ms --filter time.parse_timestamp \
  --samples 11 --time 100ms
```

Keep measurements and campaign records outside the repository. Correctness and
error identity belong in the native and called source tests, not timing limits.
