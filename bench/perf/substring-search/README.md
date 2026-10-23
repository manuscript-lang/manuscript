# Substring-search regression (#918)

Run the bounded harness with:

```sh
cargo run --release --locked -p ms-rt --example substring_search
```

The harness calls the actual runtime `find` and `rfind` helpers. It checks each
answer against a slice-window model before timing, consumes every result, and
checks/prints the accumulated checksum after timing. Allocation, compilation,
and the reference model are outside the timed region. There are no timing
assertions. The largest case is 262,144 haystack bytes and 16,384 needle bytes.

For a before/after comparison, build the same example on each revision (copy
`crates/ms-rt/examples/substring_search.rs` into the baseline checkout), save the
two executables, warm each once, then run five alternating before/after pairs
without concurrent builds. Compare medians per case, direction, and size; verify
identical checksums in every pair. `samples.csv` retains every measured sample.

The near-miss case has an all-`a` haystack and an all-`a` needle except for one
middle `b`. Both first/last-byte filters pass at every candidate; verifying the
middle repeatedly causes quadratic work. Reverse slice comparisons have the
same problem. The patch uses the already locked `memchr` 2.8.3 search routines,
which document O(haystack length + needle length) time and O(1) auxiliary space.
The single-byte forward path stays unchanged.

These are per-search bounds, not a guarantee for an entire split or replacement
operation. Allocations, output sizes, repeated searches, and String byte-to-scalar
index conversion have their own costs. Measurements are Linux x86_64 only and
are evidence for this workload, not proof of complexity or a CI performance gate.

## Recorded comparison

Measured 2026-10-23 on Linux x86_64, AMD EPYC 9V74 (5 exposed CPUs),
Rust 1.99.1, Cargo release profile with the repository's frame-pointer flags.
Baseline: `97c6921c35409f92a8e1eb5936ab5ca7568416e3`; patched: the accompanying
`string.rs` repair. Five alternating pairs, after one warm-up per executable,
with no concurrent builds or test runs. Every pair had identical checksums.

| Case | Direction | Hay / needle bytes | Before ns/search | After ns/search |
| --- | --- | ---: | ---: | ---: |
| near_miss | forward | 65536 / 4096 | 1,675,729.2 | 98,670.6 |
| near_miss | reverse | 65536 / 4096 | 1,621,966.8 | 46,575.7 |
| near_miss | forward | 131072 / 8192 | 6,701,372.9 | 194,270.0 |
| near_miss | reverse | 131072 / 8192 | 6,180,683.3 | 97,052.6 |
| near_miss | forward | 262144 / 16384 | 24,531,146.8 | 391,088.5 |
| near_miss | reverse | 262144 / 16384 | 24,403,686.4 | 187,162.9 |
| prose | forward | 5760 / 5 | 6.9 | 37.4 |
| prose | reverse | 5760 / 5 | 79.8 | 25.9 |
| prose | forward | 5760 / 6 | 330.6 | 191.9 |
| prose | reverse | 5760 / 6 | 14,349.3 | 763.6 |
| prose | forward | 5760 / 1 | 4.3 | 4.9 |
| prose | reverse | 5760 / 1 | 6.8 | 13.6 |
| prose | forward | 5760 / 0 | 3.8 | 4.1 |
| prose | reverse | 5760 / 0 | 4.1 | 2.2 |
| end_hit | forward | 8198 / 6 | 470.9 | 259.0 |
| end_hit | reverse | 8198 / 6 | 4.3 | 25.8 |

At 262 KiB the pathological forward/reverse searches improve about 63x/130x;
doubling both sizes now takes about twice as long instead of about four times.
Ordinary misses and the forward end hit improve, but early forward prose hits
rise from 6.9 to 37.4 ns and reverse end hits from 4.3 to 25.8 ns. Reverse
single-byte hits also rise from 6.8 to 13.6 ns. These small absolute setup costs
are retained explicitly; this repair is not a universal speedup. Differences
of fractions of a nanosecond on unchanged short paths are measurement noise.

Executable SHA-256 (saved before/after running the same harness):

- Before: `cc0d3fca8abf1f2b29444f85e307b15cac2e8d5ec79253ae4a3c6d587a0a00fd`
- After: `05b1a41cb083ef9125259666a071013a63a7259c5f30c2ae3a793458bb77198e`
- Harness source: `94ee3492da24b3a0d8dc4e1e31aeb3dcf5d60e3d9ba2a094533685f1a6e64955`
