# Numeric timestamp tokens

## 2026-11-12

`Timestamp.format` renders padded numeric tokens directly into its existing token
buffer instead of invoking general integer formatting. Token matching, lazy token
reuse, calendar/zone resolution, errors, output UTF-8 handling and allocation
policy remain unchanged. There is no unsafe code or public API change.

Baseline: `a80431c01c2576747a105d1b28bc51762d72895b`, including the earlier
[output-buffer improvement](../time-format/README.md). The latest whole-suite
[dated baseline](../baseline-2026-10-28.md) has no identical pattern-format case;
these comparisons use freshly built baseline/candidate programs on one machine.
[Metadata](results-2026-11-12/metadata.json) records executable/source hashes,
compiler flags, LLVM Release sidecars and the host. Both native binaries and
the baseline compiler are retained in `/workspace/scratch/numeric-format/` in
the investigation workspace.

Linux x86_64, AMD EPYC 9V74 shared VM, Rust 1.99.1, native Manuscript LLVM Release.
The runner pins parent and children to one permitted CPU and sets
`MS_CPU_LEVEL=baseline` at execution (the runtime dispatcher reads it then).
Inputs are runtime arguments. Timestamp construction and expected-text generation
precede timing; each timed call produces an owned formatted value whose byte
length contributes to a checked checksum. Every process also emits the exact
text once; paired outputs must match byte for byte.

Each case has three warmup pairs then 25 measured pairs, alternating execution
order. No builds or other benchmarks run during the timed series. The table is
the median paired candidate/baseline ratio; lower is faster. Raw samples and
P10–P90 variation are in [samples.json](results-2026-11-12/samples.json).

| Pattern | UTC | America/New_York | +05:30 |
| --- | ---: | ---: | ---: |
| empty | 0.759 | 0.908 | 0.850 |
| literal | 0.871 | 0.975 | 0.910 |
| year | 0.757 | 0.891 | 0.846 |
| date | 0.679 | 0.810 | 0.724 |
| full | 0.623 | 0.705 | 0.627 |
| unicode | 0.803 | 0.871 | 0.798 |
| long | 0.987 | 1.002 | 1.017 |

UTC date formatting: **139.48 → 95.45 ns**; full date/time/offset/zone:
**290.52 → 181.56 ns**. Empty, literal, single-year and raw negative/extended
field controls establish no material regression. Raw negative year, year 10000
via offset, and wide negative nanosecond ratios are 0.525, 0.663 and 0.824.

Long repeated patterns are unchanged within noise. The initial +05:30 ratio
1.017 was checked with five-times-longer batches: median A/B **0.9868**, A/A
**0.9986**, across another 25 measured pairs each. See
[long-confirm.json](results-2026-11-12/long-confirm.json). Ordinary A/A medians
were 0.992 (empty), 0.994 (year) and 1.007 (date). Gains on empty patterns mean
not every full-function difference can be attributed solely to digit arithmetic.

### Optimized C control

`utc.c` uses the same nine tokens, per-call UTC conversion, a year-range check,
fresh owned output, cached token values and direct padded-digit emission.
Nanoseconds are validated during setup. Build with GCC 14.2.0 and
`-O3 -march=x86-64 -mtune=generic -std=c11`. C results are an equivalent valid
UTC/year-1-through-9999 subset, not named-zone/error API or whole-language parity.
C constructs valid UTF-8 from valid patterns; Manuscript retains output validation.

| Pattern | C ns/call | Candidate ns/call | Paired candidate/C |
| --- | ---: | ---: | ---: |
| empty | 46.85 | 54.07 | 1.155 |
| literal | 66.33 | 66.77 | 1.003 |
| year | 50.52 | 71.23 | 1.397 |
| date | 70.11 | 95.55 | 1.354 |
| full | 136.45 | 171.33 | 1.257 |
| unicode | 172.78 | 147.76 | 0.859 |
| long | 6604.88 | 4329.61 | 0.658 |

The fix narrows the date/full gap to roughly 1.35x/1.26x this C control; it does
not establish C parity.

### Correctness and reproduction

- `padded_tokens_match_standard_integer_formatting`: 4096 signed edge/random
  values at widths 2/3/4 against Rust's original integer-format contract,
  including i64::MIN, zero, signs and non-truncating minimum widths.
- `format_preserves_signed_raw_fields_and_minimum_widths`: negative/extended
  years, extreme raw nanoseconds and signed offsets against the eager oracle.
- Existing oracle comparisons retain Unicode, invalid raw UTF-8, repeated and
  incomplete tokens, historical named zones, empty formats and invalid-zone errors.
- The public time fixture adds a negative-year/wide-nanosecond assertion; all
  12 tests pass with both baseline and candidate compilers. The 50 unit tests
  and two time integration tests also pass.

Build the baseline and candidate `main.ms` with their respective Release
compilers into a scratch directory as `base` and `new`. Preserve the binaries
and adjacent sidecars; verify both say LLVM/Release. This investigation used
identical source bodies with baseline/candidate comment labels. Build the C
control in the same directory as `c-utc`, then run sequentially:

```sh
cc -O3 -march=x86-64 -mtune=generic -std=c11 utc.c -o SCRATCH/c-utc
python3 run.py SCRATCH
python3 confirm.py SCRATCH
```

The scripts verify exact outputs and write samples and executable identities to
the scratch directory. `samples.json` records the exact arguments and iteration
counts: ordinary calls use 500,000 iterations, empty 1,000,000, and the
128-repeat long pattern 10,000; the confirmation uses 50,000 long calls.
The C comparison uses one million ordinary calls.

No instruction-count claim is made (hardware profiling tools were unavailable).
Performance was measured on Linux x86_64 only; the change is platform-neutral
integer rendering. Full required Linux CI is the merge gate.
