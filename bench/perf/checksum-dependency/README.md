# Shorten the CRC-32 carried dependency

The existing shared native CRC-32 uses the same IEEE slicing-by-eight algorithm
before and after this change. Four table terms depend on the rolling register;
four depend only on the next input bytes. Combine the independent terms first,
so they can be prepared while the prior block's register is becoming available.
The captured native disassembly confirms that ordering on this measured build.
There are no new thresholds, tables, dependencies, unsafe accesses or algorithms.

## Reproduce

Build the runtime and release compiler at the baseline and candidate revisions.
Copy this harness to the baseline checkout without changing its library. Build
`main.ms` with `target/release/ms build <main.ms> --build-type Release -o <dir>/ms`
at baseline, and `-o <dir>/new` at candidate. Compile the C control and copy the
baseline for A/A, then run:

```sh
cc -std=c17 -O3 -march=x86-64 -mtune=generic -Wall -Wextra -Werror bench/perf/checksum-dependency/control.c -o /tmp/checksum/c
cp /tmp/checksum/ms /tmp/checksum/ms-aa
python3 bench/perf/checksum-dependency/run.py base /tmp/checksum
python3 bench/perf/checksum-dependency/run.py candidate /tmp/checksum
python3 bench/perf/checksum-dependency/run.py aa /tmp/checksum
```

The runner pins CPU4 on Linux. Inputs are runtime-generated from identical byte
and seed formulas outside timing. Both APIs borrow input bytes and return scalar
checksums without allocating. Each timed call compares its complete UInt32 result
with an independent Python zlib oracle and contributes to a checked aggregate.
One hundred warm calls precede timing. Whole-input and public seeded incremental
updates use the same chunk boundaries, including a final empty update. C uses the
same reflected IEEE polynomial and slicing-by-eight recurrence. Its Adler control
uses the same RFC1950 recurrence, 5,552-byte reductions and explicit unrolling;
it substitutes no hash algorithm. A C-only memory barrier prevents invariant input
hoisting. The API byte/state operations here have no expected error return.
ReadStream wrappers, close/error propagation and cryptographic digest algorithms
are not being compared against the pointer-based C control.

## 2026-11-12

Baseline main: `5082ec904cfbe1f71f42e7cdbfc4b4e818c201e6`. Linux x86_64,
AMD EPYC 7763, pinned CPU4, rebuilt runtime and compiler, LLVM Release programs.
The [2026-10-28 suite baseline](../baseline-2026-10-28.md) has no matching CRC
case; this is a new focused before/after suite, not an overall performance claim.
Twenty-one alternating pairs per case; no builds or other benchmark workers ran
concurrently. No samples were removed from the final runs. Initial qualification
used C-v3 flags and stopped on an empty-Adler oracle mismatch; those incomplete
trials are excluded. Final runs use baseline x86-64 C flags and the corrected
oracle. Neither perf nor Callgrind was available; no instruction-count claim is made.

Public Adler32 state is any UInt32. An empty update returns it unchanged, even
when its halves exceed 65520. Python zlib normalizes that state on an empty input,
so the independent oracle explicitly retains the seed in this documented case.
No production behavior was changed to fit the oracle.

[Raw data, executable hashes, source provenance, page faults and assembly](results-2026-11-12/)
retain all final cases. Historical raw columns are named `ms` and `c`: the metadata
explicitly maps `base` to MS/C, `candidate` to baseline MS/candidate MS, and `aa` to
identical baseline binaries. C flags and the C barrier apply only to `base`.

Median ns per whole-input CRC call, including result comparison/checksum work:

| Bytes | Baseline MS | Candidate MS |
| --- | ---: | ---: |
| 0 | 2.23 | 2.23 |
| 1 | 2.89 | 2.88 |
| 7 | 7.40 | 7.40 |
| 8 | 3.84 | 3.84 |
| 9 | 4.55 | 4.54 |
| 15 | 10.54 | 10.34 |
| 16 | 6.45 | 5.94 |
| 17 | 7.14 | 6.91 |
| 64 | 28.02 | 23.36 |
| 256 | 150.10 | 109.93 |
| 1,024 | 609.70 | 455.01 |
| 65,535 | 40,450.16 | 29,912.88 |
| 65,536 | 40,049.56 | 29,641.23 |
| 65,537 | 40,864.57 | 29,781.53 |
| 1,048,576 | 648,555.36 | 485,556.34 |
| 1,048,577 | 645,739.43 | 483,029.70 |

Seven-byte seeded chunks remain effectively unchanged. Seeded 4,096-byte chunks
over 64 KiB improve 39.55→29.89 µs. Unchanged Adler controls are within about 1%;
A/A Adler on one byte varied +2.3%. On the C comparison, baseline MS/C measured
40.58/29.89 µs at 64 KiB and 645.54/478.59 µs at 1 MiB. The candidate reaches
29.64 and 485.56 µs in its separate paired baseline run. These are same-algorithm
observations on this host; the dependency ordering is not a universal hardware
speed guarantee. The raw page-fault controls retain the entire process counts,
including untimed input construction; they are not isolated kernel fault counts.

Existing native bitwise-oracle tests cover every alignment, tails, continuation,
empty states and arbitrary CRC seeds. Called checksum and stream fixtures cover
public results. No new correctness tests mirror the regrouped XOR expression.
The bounded inventory also found FNV-1/FNV-1a 32/64-bit, CRC64 ECMA/ISO and MapHash
in crypto/hash.ms, and the existing RustCrypto-backed digest APIs in crypto.ms.
They were left unchanged without a separately qualified measured candidate.
