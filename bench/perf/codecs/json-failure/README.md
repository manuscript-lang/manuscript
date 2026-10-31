# JSON syntax-error classification

This Linux diagnostic benchmark covers Release runtime parsing after an immediately
invalid prefix, with flat plain or escaped suffixes. It separately exercises
untyped tree parsing and typed String/document parsing, plus valid-input controls.
It does not measure compiler latency or nested/depth behavior.

Input generation, process launch, compilation and reporting are outside the timed
loop. Each parse must return the exact expected error or the complete expected
string payload. Two clocks bracket the loop: ordinary monotonic wall time and a
small C helper using `CLOCK_PROCESS_CPUTIME_ID`. The CPU interval also encloses the
wall-clock queries. CPU time excludes ordinary descheduling, but both clocks still
reflect frequency/cache variability and VM effects. Retain both distributions.

Build both native archives with the pinned Rust toolchain and
`cargo xtask runtime`. The measured baseline is
`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`; reconstruct the measured native change
with `git apply --unidiff-zero evidence-2026-10-29/fix.patch`. Use one compiler for
both generated programs and explicit absolute native archive paths:

```sh
cc -O2 -std=c11 -Wall -Wextra -Werror -c bench/perf/codecs/json-failure/cpu.c -o /tmp/json-cpu.o
MS_RT_LIB=/absolute/runtime-before.a target/release/ms build \
  bench/perf/codecs/json-failure/ms.toml --build-type Release \
  --link /tmp/json-cpu.o -o /tmp/json-before
MS_RT_LIB=/absolute/runtime-after.a target/release/ms build \
  bench/perf/codecs/json-failure/ms.toml --build-type Release \
  --link /tmp/json-cpu.o -o /tmp/json-after
python3 bench/perf/codecs/json-failure/compare.py \
  /tmp/json-before /tmp/json-after /tmp/json-comparison --pairs 9
```

Use the same pinned `MS_LLVM_TOOLS`, writable cache and optimization settings.
Verify actual `opt`/`llc` execution; reject an unexpected Cranelift fallback.
Finish compilation and other substantial CPU work before timing. The runner
alternates producer order, discards one warm-up pair, checks every producer's exit
status, exact case/count/checksum and positive clocks, and retains all samples.
It publishes a summary and marks its manifest complete only after every case
succeeds. Output directories must be new, preventing stale/partial evidence reuse.
There is no timing threshold in CI.

For deterministic work counts, collect only the corresponding native entry:

```sh
valgrind --tool=callgrind --collect-atstart=no \
  --toggle-collect=msrt_json_parse_tree /tmp/json-before 65536 3 escaped
valgrind --tool=callgrind --collect-atstart=no \
  --toggle-collect=msrt_json_parse /tmp/json-before 65536 3 typed-escaped
```

Repeat for the after binary. Require successful output/checksums; these instruction
counts are separate from native wall-time measurements. The
[2026-10-29 report](results-2026-10-29.md) retains all measured cases and identities.
Windows/macOS clock-helper portability has not been verified.
