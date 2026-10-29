# Rejected one-byte reverse-search specialization

**Rejected; evidence only.** Baseline native source is
`db975ce2f01ddf8da108ec9045ecaf66a63ab22c`. The direct-`memrchr` specialization
improved some controls but repeatedly worsened common end hits and other public
`String.last_index_of` cases. Production `string.rs` is restored byte for byte to
the baseline. No retained runtime change, active e2e fixture or PR is planned.
The archived patch includes the candidate and its native correctness test only.

Root’s duplicate check found that #1034 already recorded a general reverse-end-hit
tradeoff and explicitly deferred tiny fast paths. This experiment tests a new
one-byte specialization for that known tradeoff; it does **not** establish a
newly discovered general bug. The historical broad substring benchmark was not
rerun. This is separate from rejected split-searcher caching, and no quote,
compiler/codegen, ownership or allocation-internals investigation occurred.

## Hypothesis, configuration and correctness

Local `rfind` forwards nonempty needles to memchr 2.8.3 `memmem::rfind`, whose
public wrapper uses Rabin–Karp for haystacks below 64 bytes. The candidate instead
returns `memchr::memrchr` for one-byte needles, retaining empty, oversized and
multi-byte paths. Longer one-byte searches already reach dependency `memrchr`;
removing short substring/hash work did not establish an end-to-end win.

Matched baseline and candidate runtime archives were built from this same
worktree path and saved under `/tmp/string-round2/rfind-{before,after}`. Both
helpers are byte-identical, SHA-256
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.
Both phases used the same pinned compiler, SHA-256
`cd158b8ca24e62776ba38aa8b774e57f4dd1434346d2edc7569211e7b848c0fc`, built at
`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`, with explicit cached `MS_LLVM_TOOLS`.
Normal public CLI JSON and companion metadata are copied verbatim under
[build-metadata](build-metadata/). All four program companions report **Cranelift,
Release**. Effective optimization beyond those labels was not independently
verified; no backend, code-placement, assembly or helper-generation probe occurred.

Candidate native string tests passed **21/21**, including every byte 0–255 and
subslice boundaries with outside matches ignored. The exact command and exit are
in the saved build records; logs retain results. Every generated-program producer,
identity, exact-output/status and checksum guard passed in both phases. These
are correctness observations, not justification for retaining a slower candidate.
Full repository/corpus gates were not pursued for this rejected experiment.

## Public contract, oracle and operation

The public API was confirmed with `ms search_symbol` from a small `/tmp` cwd:
`String.last_index_of(value: String) Optional[Int]` returns a Unicode scalar index;
empty value matches at scalar length. `.get(-1)` represents absence because a
successful index is nonnegative. `clock().now()` supplies monotonic readings.

All 101 cases use fixed expected scalar positions from literal placement/count
formulas, independently verified by Python Unicode `str.rfind`. No measured
Manuscript operation constructs an oracle. `oracle.json` preserves expected
indexes and construction expressions. There are 55 one-byte, 14 empty-needle,
seven two-byte, ten longer-needle, ten Unicode and five NUL cases. ASCII haystack
lengths are 0/1/2/7/15/16/31/32/63/64/65/128/4096/1048576, with start/end/interior/
miss and repeated near-end hits. Bounded 4 KiB repetitive/multi-byte/overlap
controls retain the prior complexity repair. The decisive tiny `"ac"` / `"ab"`
miss has equal valid lengths and reaches the added branch. Unicode includes
multi-byte/multi-scalar needles, combining marks and scalar indexes distinct from
byte positions, including a 36,865-byte scaling case.

Each timed call extracts and checks the exact index and consumes `actual + 19`.
Any mismatch contributes −1, whereas valid contributions are at least 18, so it
fails the final checked checksum. Public byte search, successful-prefix scalar
counting, Optional extraction, result checking and checksum arithmetic are timed.
Setup, expected construction, checked warm-up, compilation, process startup and
printing are excluded. These are public end-to-end timings, not isolated search
kernel measurements. Invalid internal UTF-8 and other excluded machinery were
not investigated.

## Two preserved phases and rejection

Recorded 2026-10-29 on the coordinated Intel Xeon Platinum 8573C Linux VM, five
exposed CPUs, Linux 6.18.55. Runner/producers use CPU 0 with alternating before/
after process order and no concurrent builds/tests/timings. Other platforms and
application input frequencies were not measured. Ratio-of-medians and paired
candidate-minus-baseline deltas are separate statistics; all ranges/outliers stay.

The initial full phase preserves **1414 rows**, 101 cases × two variants × seven
pairs, in `samples.csv`; `summary.csv`, `paired.csv` and `paired-samples.csv`
preserve all medians/ranges/signs and 707 normalized pairs. The confirmation
repeats **all 101 cases**, not a selected winning subset: **1818 rows**, two
variants × nine pairs, in `confirmation-samples.csv`, with corresponding summary/
paired files and all 909 normalized pairs. The combined 3232 raw rows are never
pooled. Case construction and expected outputs are identical; confirmation changes
only intervals through 128 input bytes from one million to three million calls.
Other counts remain 100,000 for intermediate inputs, 65,536 from 4 KiB, 4096
from 16 KiB and 256 from 256 KiB. Separate processes/order and allocator/cache conditions can differ.

Repeated unfavorable costs drive rejection. Their initial results are:

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `one_end_n128` | 50.340 | 64.638 | +28.40% | +13.719 | 7/7 |
| `one_end_n4096` | 89.992 | 112.935 | +25.49% | +19.809 | 7/7 |
| `one_many_n4096` | 90.246 | 107.400 | +19.01% | +16.045 | 6/7 |
| `two_tiny_valid_length_miss` | 8.220 | 9.764 | +18.78% | +1.354 | 6/7 |
| `unicode_combining_needle` | 25.882 | 31.950 | +23.45% | +5.506 | 7/7 |
| `unicode_multibyte_needle` | 35.940 | 39.578 | +10.12% | +2.618 | 7/7 |

The same cases in the longer confirmation phase are:

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `one_end_n128` | 53.656 | 66.243 | +23.46% | +14.291 | 8/9 |
| `one_end_n4096` | 103.138 | 137.584 | +33.40% | +34.446 | 8/9 |
| `one_many_n4096` | 98.589 | 126.705 | +28.52% | +28.252 | 7/9 |
| `two_tiny_valid_length_miss` | 8.796 | 10.436 | +18.65% | +1.381 | 7/9 |
| `unicode_combining_needle` | 26.962 | 33.127 | +22.87% | +6.469 | 9/9 |
| `unicode_multibyte_needle` | 39.020 | 41.387 | +6.07% | +3.301 | 6/9 |

In particular, paired confirmation costs are +14.291 ns for end128 (8/9 slower),
+34.446 ns for end4096 (8/9), +28.252 ns for repeated-hit4096 (7/9), +1.381 ns for
the tiny valid-length two-byte miss (7/9), +6.469 ns for the combining-mark needle
(9/9), and +3.301 ns for the Unicode multi-byte needle (6/9). Some of these paths
retain the same logical search algorithm; this does not establish why every
cost moved. No placement or codegen explanation was inferred or tuned. The
repeated public-operation costs suffice to reject this candidate; short-search
gains do not cancel a material cost elsewhere.

## Every unfavorable initial median

All unfavorable initial medians follow, including per-variant min/max and paired
delta ranges. The raw CSVs also retain every favorable and mixed-sign case.

| Case | Before median [min,max] ns | After median [min,max] ns | Change | Paired delta median [min,max] ns | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `one_miss_n1` | 8.543 [7.494, 34.783] | 9.045 [7.935, 10.550] | +5.89% | -0.107 [-24.233, +2.223] | 3/7 |
| `empty_needle_n1` | 6.549 [5.842, 8.353] | 6.834 [5.785, 7.310] | +4.34% | -0.252 [-1.520, +0.734] | 3/7 |
| `one_miss_n2` | 8.288 [7.961, 11.194] | 9.977 [9.354, 17.749] | +20.37% | +1.857 [-1.258, +9.340] | 6/7 |
| `empty_needle_n15` | 5.765 [5.000, 11.367] | 6.256 [5.320, 8.788] | +8.51% | -0.445 [-5.164, +3.528] | 3/7 |
| `empty_needle_n16` | 5.566 [4.632, 6.826] | 6.255 [5.387, 7.852] | +12.39% | +0.629 [-0.738, +2.762] | 5/7 |
| `empty_needle_n128` | 11.261 [10.727, 16.324] | 11.542 [10.449, 12.288] | +2.50% | -0.278 [-4.647, +1.085] | 3/7 |
| `one_end_n128` | 50.340 [47.673, 52.031] | 64.638 [62.447, 70.031] | +28.40% | +13.719 [+11.013, +20.153] | 7/7 |
| `one_end_n4096` | 89.992 [83.832, 100.661] | 112.935 [103.641, 163.077] | +25.49% | +19.809 [+8.096, +62.416] | 7/7 |
| `one_miss_n1048576` | 15497.629 [13822.758, 19149.148] | 16956.902 [15233.191, 20128.496] | +9.42% | +1409.875 [-1250.680, +3301.082] | 5/7 |
| `empty_needle_n1048576` | 18730.238 [16145.137, 21303.012] | 20672.035 [15620.883, 24815.082] | +10.37% | +1172.242 [-2319.188, +6452.605] | 5/7 |
| `one_end_n1048576` | 17459.223 [15929.180, 30956.613] | 18462.238 [16094.043, 68182.297] | +5.74% | +571.762 [-6325.191, +37225.684] | 5/7 |
| `one_many_n4096` | 90.246 [84.610, 111.640] | 107.400 [100.654, 132.521] | +19.01% | +16.045 [-4.240, +38.235] | 6/7 |
| `one_many_n1048576` | 17406.387 [15346.375, 21006.395] | 18618.945 [16485.344, 25489.777] | +6.97% | +1138.969 [-1132.848, +4483.383] | 6/7 |
| `two_tiny_valid_length_miss` | 8.220 [7.683, 12.712] | 9.764 [8.679, 12.640] | +18.78% | +1.354 [-0.072, +2.169] | 6/7 |
| `two_boundary_miss` | 48.309 [45.201, 54.700] | 51.497 [44.930, 53.042] | +6.60% | +1.748 [-1.754, +6.106] | 4/7 |
| `two_repeated_last` | 13.398 [11.625, 18.962] | 14.035 [12.028, 16.363] | +4.75% | +1.111 [-5.222, +4.153] | 4/7 |
| `multi_empty_hay` | 6.353 [5.492, 14.160] | 6.434 [5.693, 6.908] | +1.27% | +0.272 [-7.726, +1.127] | 4/7 |
| `multi_near_match_miss` | 68.382 [63.132, 71.390] | 69.381 [66.567, 70.917] | +1.46% | +1.520 [-2.001, +4.000] | 4/7 |
| `multi_large_end` | 109.429 [101.611, 129.257] | 128.790 [126.562, 174.477] | +17.69% | +26.131 [-1.772, +69.417] | 6/7 |
| `multi_repetitive_end` | 1349.151 [1276.314, 1444.718] | 1368.626 [1302.558, 1676.785] | +1.44% | +26.244 [-66.189, +232.068] | 4/7 |
| `multi_repetitive_overlap` | 1511.031 [1472.252, 1602.505] | 1521.426 [1461.201, 3921.494] | +0.69% | +18.746 [-101.838, +2410.463] | 4/7 |
| `unicode_two_end` | 85.737 [82.547, 95.535] | 93.655 [86.924, 97.648] | +9.24% | +7.843 [-8.610, +11.108] | 6/7 |
| `unicode_multibyte_needle` | 35.940 [33.786, 39.041] | 39.578 [38.206, 53.936] | +10.12% | +2.618 [+0.974, +18.772] | 7/7 |
| `unicode_empty_needle` | 25.552 [23.553, 28.101] | 27.533 [24.193, 32.607] | +7.75% | +1.383 [-1.359, +8.275] | 4/7 |
| `unicode_combining_needle` | 25.882 [24.848, 28.398] | 31.950 [28.950, 39.583] | +23.45% | +5.506 [+3.414, +14.378] | 7/7 |
| `unicode_large_scalar_index` | 52296.206 [50631.182, 53142.394] | 54076.759 [52539.472, 64523.610] | +3.40% | +1908.289 [+806.207, +12258.634] | 7/7 |
| `nul_hay_miss` | 9.626 [9.151, 11.937] | 10.289 [8.967, 13.522] | +6.88% | +0.662 [-1.305, +1.759] | 5/7 |

## Every unfavorable confirmation median

These remain a separate workload/interval phase, with all original rows/ranges.

| Case | Before median [min,max] ns | After median [min,max] ns | Change | Paired delta median [min,max] ns | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `one_miss_n1` | 8.503 [7.258, 20.673] | 9.524 [8.414, 10.410] | +12.01% | +1.252 [-11.566, +2.117] | 8/9 |
| `empty_needle_n1` | 6.507 [5.773, 11.793] | 6.688 [5.631, 7.608] | +2.79% | +0.377 [-5.755, +1.101] | 5/9 |
| `one_miss_n2` | 9.144 [8.072, 10.886] | 9.363 [9.140, 10.460] | +2.40% | +0.769 [-1.702, +1.654] | 6/9 |
| `empty_needle_n7` | 6.526 [5.838, 8.980] | 6.599 [5.496, 7.684] | +1.12% | -0.086 [-2.055, +1.149] | 4/9 |
| `empty_needle_n16` | 5.643 [5.060, 7.495] | 6.381 [5.523, 9.454] | +13.09% | +0.418 [-0.573, +2.365] | 6/9 |
| `one_end_n128` | 53.656 [50.713, 120.076] | 66.243 [62.189, 122.516] | +23.46% | +14.291 [-54.863, +68.860] | 8/9 |
| `one_miss_n4096` | 60.019 [53.612, 151.769] | 65.271 [50.225, 89.197] | +8.75% | +7.318 [-96.506, +32.191] | 5/9 |
| `empty_needle_n4096` | 63.931 [54.103, 278.917] | 73.805 [54.185, 127.699] | +15.44% | +12.896 [-220.788, +73.596] | 5/9 |
| `one_end_n4096` | 103.138 [85.750, 258.299] | 137.584 [106.769, 273.099] | +33.40% | +34.446 [-151.530, +165.806] | 8/9 |
| `one_many_n4096` | 98.589 [84.504, 127.376] | 126.705 [104.693, 326.770] | +28.52% | +28.252 [-7.350, +199.394] | 7/9 |
| `two_tiny_hit` | 13.657 [12.345, 14.601] | 15.693 [13.062, 20.902] | +14.91% | +2.908 [-1.539, +8.557] | 8/9 |
| `two_tiny_valid_length_miss` | 8.796 [7.598, 10.741] | 10.436 [8.851, 14.120] | +18.65% | +1.381 [-0.626, +5.391] | 7/9 |
| `two_boundary_miss` | 52.430 [47.453, 465.998] | 55.952 [49.363, 388.118] | +6.72% | +6.767 [-408.214, +335.688] | 5/9 |
| `multi_overlap` | 13.231 [12.772, 17.241] | 15.397 [12.879, 20.308] | +16.37% | +2.024 [-0.974, +6.398] | 7/9 |
| `multi_large_end` | 122.592 [104.815, 183.113] | 133.366 [124.601, 206.843] | +8.79% | +3.820 [-56.584, +101.701] | 6/9 |
| `multi_repetitive_end` | 1332.252 [1249.961, 2455.380] | 1381.833 [1277.321, 1896.309] | +3.72% | +60.951 [-1158.167, +525.432] | 6/9 |
| `multi_repetitive_overlap` | 1539.883 [1455.211, 1994.683] | 1640.151 [1496.679, 1994.175] | +6.51% | +43.985 [-354.532, +522.836] | 6/9 |
| `unicode_two_end` | 92.698 [84.343, 116.536] | 94.831 [88.246, 107.763] | +2.30% | +4.765 [-28.290, +13.121] | 7/9 |
| `unicode_multibyte_needle` | 39.020 [35.981, 44.001] | 41.387 [40.337, 54.410] | +6.07% | +3.301 [-1.402, +14.143] | 6/9 |
| `unicode_empty_needle` | 27.289 [25.362, 28.188] | 27.545 [25.864, 32.676] | +0.94% | +0.385 [-1.164, +7.314] | 6/9 |
| `unicode_combining_needle` | 26.962 [25.601, 28.611] | 33.127 [31.235, 60.396] | +22.87% | +6.469 [+4.211, +33.434] | 9/9 |
| `unicode_large_scalar_index` | 51903.618 [50152.469, 148730.068] | 54382.779 [52299.085, 134679.328] | +4.78% | +3281.776 [-94347.289, +82823.312] | 6/9 |

## Initial costs that reversed direction

The following initially unfavorable medians improved in confirmation. They are
**unconfirmed initial costs**, not proof of a stable regression and not erased
from the first phase. Other full/confirmation differences remain in their CSVs.

| Case | Before median ns | After median ns | Change | Paired delta ns | Slower |
| --- | ---: | ---: | ---: | ---: | ---: |
| `empty_needle_n15` | 6.356 | 6.226 | -2.04% | -0.180 | 3/9 |
| `empty_needle_n128` | 12.489 | 11.570 | -7.36% | -1.068 | 3/9 |
| `one_miss_n1048576` | 18568.566 | 16267.254 | -12.39% | -2516.918 | 3/9 |
| `empty_needle_n1048576` | 19787.734 | 18960.758 | -4.18% | -625.254 | 4/9 |
| `one_end_n1048576` | 23370.242 | 20582.051 | -11.93% | -2788.191 | 3/9 |
| `one_many_n1048576` | 20202.422 | 19977.402 | -1.11% | +1988.445 | 6/9 |
| `two_repeated_last` | 13.574 | 13.524 | -0.37% | -0.143 | 4/9 |
| `multi_empty_hay` | 8.136 | 6.358 | -21.85% | -0.996 | 2/9 |
| `multi_near_match_miss` | 75.287 | 68.385 | -9.17% | -8.292 | 2/9 |
| `nul_hay_miss` | 10.057 | 9.981 | -0.75% | +0.071 | 5/9 |

## Reproducibility and restored source

`generate.py` reproduces the original unformatted source and independent oracle.
`generated-before-format.ms.txt` preserves those exact bytes; pinned `ms fmt`
produced measured `main.ms`. `prepared.json` is an immutable historical
preparation record: its original README hash refers to
`exploratory/preparation-README.md`, and its original `main.ms` hash refers to
`generated-before-format.ms.txt`. Its initial pending labels describe preparation,
not the final outcome. `builds.json` holds the current complete file/hash map,
source snapshots, exact commands, programs, archives, helpers and public metadata.
`confirmation.ms` differs only in the short iteration count described above.

`candidate-runtime.patch` remains an immutable rejected artifact, including the
native test. `patch-replay.json` proves pure in-memory replay against the saved
baseline yields the saved candidate exactly, and that current production bytes
match baseline. No runtime patch was applied while preparing this report. The
shared runner’s independently reviewed strict `--identity-file` extension is
included in `bench/perf/string-lines/compare.py`, preserving default line cases.
It rejects failed producers, malformed headers, missing/duplicate/unknown cases,
nonpositive elapsed times or changed identity/checksum tuples before reporting.

Historical reproduction, only in a separately coordinated window with both saved
archives and the pinned compiler, uses normal `ms build ... --build-type Release
--json`, then:

```sh
taskset -c 0 python3 bench/perf/string-lines/compare.py /tmp/string-round2/rfind-before/program /tmp/string-round2/rfind-after/program /tmp/rfind-replay.csv --pairs 7 --identity-file bench/perf/string-rfind/identities.json
taskset -c 0 python3 bench/perf/string-lines/compare.py /tmp/string-round2/rfind-before/confirmation-program /tmp/string-round2/rfind-after/confirmation-program /tmp/rfind-confirmation-replay.csv --pairs 9 --identity-file bench/perf/string-rfind/confirmation-identities.json
```

Do not overwrite recorded raw data. No new measurement, runtime variation,
production PR, CI threshold or gate bypass is proposed. The untracked shared
`target` symlink is excluded from evidence commits. The saved unified patch keeps
required single-space blank context, which is an intentional evidence-only
whitespace exception rather than an instruction to trim or modify the patch.
The verbatim `logs/after-string-tests.log` also retains its generated final blank
line; it is a second evidence-only whitespace exception.
