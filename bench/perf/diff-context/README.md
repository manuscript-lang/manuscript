# Unified diff context marking

Times complete diffs with dense insertion, one sparse change, or unchanged text. Input setup and expected-output construction are outside the timer; every timed result is compared with that expected output. The native program prints elapsed nanoseconds and a consumed output-length checksum.

```sh
MS_BACKEND=cranelift ms build bench/perf/diff-context/main.ms --build-type Release -o /tmp/diff-context
/tmp/diff-context 4000 9223372036854775807 10 insert
/tmp/diff-context 1000 100 100 insert
/tmp/diff-context 1000 3 1000 insert
/tmp/diff-context 1000 3 1000 sparse
/tmp/diff-context 1000 3 1000 same
```

Use increasing insertion counts (1000, 2000, 4000) to check full-file-context scaling, and repeat ordinary controls with ten lines. Compare matching baseline and candidate builds in alternating order for at least nine pairs, pinned to one CPU where supported. Sparse mode requires a positive line count. Dense insertion isolates context work without a two-dimensional longest-common-subsequence table.
