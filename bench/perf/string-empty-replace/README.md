# Empty boundary replacement: rejected candidate

Based on pinned main `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.
The candidate is **rejected** because ordinary insertion/control costs recur in
the focused comparison. The runtime is restored exactly to baseline, with no
active fixture. The tested patch and source tests are archived in `exploratory/`.
This branch retains evidence and the shared identity-file runner extension only.

## Attempted work removal and correctness

`text.replace("", "")` counted all input scalars, constructed an identical
byte vector one scalar at a time, then copied through `from_buf`/`from_bytes`.
The candidate called existing `from_bytes(text)` directly for this identity case
before the scalar count. It changed no public API, constructor implementation,
allocator/cache/tag/drop machinery, or nonempty replacement algorithm. Arguments
were already evaluated before the native call. Output construction remained the
same copying constructor; input sharing or a representation redesign was not used.

[exploratory/runtime.patch](exploratory/runtime.patch) preserves the exact change.
[exploratory/source-tests.ms](exploratory/source-tests.ms) checks output and
unchanged input around short-result boundaries, Unicode/NUL, insertion, growing,
deleting, and missing matches. Both tests passed in explicit Release and Debug;
all 20 selected Rust string tests passed. Logs are preserved under [checks](checks/).
No workspace-wide/corpus result is claimed for this rejected candidate.

## Matched artifacts and configuration

Baseline and candidate archives were built from the same worktree path with
source restored on failure; `ms_rt_hot.ll` is byte-identical. The unchanged pinned
compiler SHA-256 is
`cd158b8ca24e62776ba38aa8b774e57f4dd1434346d2edc7569211e7b848c0fc`.
[builds.json](builds.json) records every source, patch, test/log, compiler, archive,
helper, program, runner, inventory, and data hash. All evidence text/CSV uses LF
before hashing. The shared `string-lines/compare.py --identity-file` extension is
included so the branch can reproduce validation independently.

Builds requested Release with explicit
`MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629` and supplied no other
backend override. Normal build JSON/stderr and companion files are copied verbatim
under [build-metadata](build-metadata/). Companions label the backend `cranelift`;
effective optimization beyond the recorded configuration is unverified in this
restricted pass. No backend/codegen probe or fallback/LLVM inference was made.

## Full 70-case comparison, 2026-10-29

Intel Xeon Platinum 8573C VM, five exposed CPUs, Linux 6.18.55, Rust 1.99.1,
static musl runtime. The matrix covers empty/cache-size input, ASCII/mixed UTF-8/NUL
patterns, tiny to 2.25MiB input, and no-op, scalar-boundary insertion, missing,
growing, and deleting operations. Expected output comes from independent literal
patterns; no replacement operation constructs an expected result.

Seven alternating CPU 0 pairs ran without concurrent native build/test/timed work.
Both checked unrecorded warm-ups and all 14 recorded producer runs returned zero;
every exact output, strict identity, and checksum check passed. An independent
static audit reconstructed all 70 identities and verified all 980 rows and summary
medians. [samples.csv](samples.csv) retains every sample; [summary.csv](summary.csv)
all before/after medians and ranges. [paired-samples.csv](paired-samples.csv) retains
every normalized pair, signed after-minus-before delta, ratio, and percent change.
[paired.csv](paired.csv) separately aggregates paired medians/signs/ranges, rather
than conflating paired ratios with the runner's ratio of medians.

Timing includes **replacement plus full-output validation**, checked checksum and
result release. Input/expected construction, startup, compilation, checked warm-up,
and CSV printing are outside each interval. The full pattern loop passes its existing input variable as expected text
for no-op/missing cases. Iterations are 200000 at up to 128 input
bytes, 4096 at up to 16384 bytes, and 32 above that.

All 14 no-op medians improved 1.854–124.414x. Those wins did not justify accepting
ordinary insertion/control costs. Every original median regression follows; times
and paired deltas are ns per operation including validation. A positive paired
delta means slower candidate execution:

| Case | Before median | After median | Median ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `cache_ascii_grow` | 50.5 | 51.1 | 0.988x | 1.777 | 4/7 |
| `cache_ascii_delete` | 33.8 | 37.4 | 0.904x | -0.996 | 3/7 |
| `ascii_0_delete` | 17.5 | 20.4 | 0.857x | 4.100 | 6/7 |
| `ascii_1_insert` | 125.0 | 127.9 | 0.978x | 3.353 | 4/7 |
| `ascii_8_insert` | 621.0 | 677.1 | 0.917x | 33.732 | 5/7 |
| `ascii_8_miss` | 40.2 | 44.8 | 0.898x | 7.734 | 5/7 |
| `ascii_4096_insert` | 266011.2 | 385488.3 | 0.690x | 31715.140 | 6/7 |
| `ascii_4096_grow` | 82012.0 | 94496.7 | 0.868x | -1803.067 | 2/7 |
| `unicode_8_insert` | 609.0 | 614.1 | 0.992x | -6.342 | 3/7 |
| `unicode_262144_insert` | 21085810.9 | 26897382.9 | 0.784x | 10700422.969 | 5/7 |
| `unicode_262144_grow` | 6745466.9 | 7803293.1 | 0.864x | 1807294.969 | 4/7 |
| `unicode_262144_delete` | 3265583.0 | 3360654.5 | 0.972x | 119448.906 | 4/7 |
| `nul_1_insert` | 98.8 | 106.4 | 0.928x | 6.100 | 5/7 |
| `nul_1_miss` | 20.9 | 22.1 | 0.945x | -0.437 | 3/7 |
| `nul_1_grow` | 41.6 | 43.8 | 0.951x | 0.906 | 4/7 |
| `nul_1_delete` | 38.1 | 40.2 | 0.950x | -3.620 | 2/7 |
| `nul_8_insert` | 499.9 | 614.0 | 0.814x | 42.210 | 7/7 |
| `nul_8_miss` | 36.2 | 53.7 | 0.674x | 6.921 | 5/7 |
| `nul_4096_insert` | 199247.3 | 220614.4 | 0.903x | 52060.510 | 6/7 |
| `nul_4096_grow` | 78674.3 | 91007.8 | 0.864x | 1299.275 | 5/7 |
| `nul_4096_delete` | 37121.2 | 42760.1 | 0.868x | -942.719 | 3/7 |
| `nul_262144_insert` | 11127222.3 | 14333588.9 | 0.776x | 3804975.719 | 7/7 |
| `nul_262144_miss` | 147645.8 | 169578.0 | 0.871x | -4822.250 | 2/7 |
| `nul_262144_grow` | 4943305.1 | 5011691.6 | 0.986x | 534034.812 | 5/7 |
| `nul_262144_delete` | 2225940.4 | 2365066.6 | 0.941x | -9153.656 | 3/7 |

## Focused 29-case control comparison

One bounded focused run preserved the runtime patch and used nine alternating
CPU 0 pairs. [focused-controls.ms](focused-controls.ms) and
[focused-identities.json](focused-identities.json) retain every selected operation.
Short intervals use 1000000 operations, inputs up to 16384 bytes use 4096, and
larger inputs use 64. Both checked warm-ups and all 18 recorded producers passed;
all 522 rows, 29 identities, and summary medians were independently audited.
[focused-samples.csv](focused-samples.csv), [focused-summary.csv](focused-summary.csv),
[focused-paired-samples.csv](focused-paired-samples.csv), and
[focused-paired.csv](focused-paired.csv) preserve every distribution and paired sign.

For cases previously emitted by the full pattern loop, focused no-op/missing
expectations use independently written literal/repeat expressions instead of
reusing the existing input variable. Thus setup, live
expected values, allocation phase, and possibly equality cost differ from the
full suite. Physical literal pooling/aliasing was not investigated. The two suites
are retained separately and **not pooled**; the focused suite does not erase or
replace the original full-suite evidence.

Insertion costs recur with consistent paired signs. ASCII 16KiB insertion changed
209.342→234.851us with six of nine slower pairs and a +18.322us paired median.
NUL 24B insertion changed 432.3→493.2ns with eight of nine slower pairs (+58.056ns
paired median), following seven of seven slower pairs in the full suite. NUL
0.75MiB insertion changed 10.120→13.190ms with all nine slower pairs (+2.901ms
paired median), following all seven slower full-suite pairs. Other controls reverse
or remain noisy; no universal regression or causal explanation is claimed.
Every focused median regression follows:

| Case | Before median | After median | Median ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `cache_ascii_insert` | 63.2 | 66.7 | 0.948x | 4.330 | 9/9 |
| `cache_ascii_miss` | 11.4 | 12.6 | 0.898x | 0.583 | 8/9 |
| `cache_ascii_delete` | 29.3 | 32.1 | 0.915x | 2.851 | 7/9 |
| `ascii_0_delete` | 11.6 | 11.9 | 0.977x | -0.292 | 4/9 |
| `ascii_1_insert` | 122.2 | 128.0 | 0.955x | 0.983 | 5/9 |
| `ascii_8_insert` | 552.8 | 578.7 | 0.955x | 35.329 | 8/9 |
| `ascii_4096_insert` | 209342.5 | 234851.0 | 0.891x | 18321.535 | 6/9 |
| `ascii_262144_insert` | 14032752.1 | 16437955.8 | 0.854x | 2405203.703 | 8/9 |
| `unicode_1_insert` | 107.4 | 133.1 | 0.807x | 22.885 | 9/9 |
| `unicode_8_insert` | 536.6 | 635.6 | 0.844x | 59.529 | 8/9 |
| `unicode_4096_insert` | 235159.5 | 249161.6 | 0.944x | 25895.844 | 8/9 |
| `unicode_262144_insert` | 15875663.4 | 18404354.8 | 0.863x | 2352475.812 | 8/9 |
| `nul_1_insert` | 88.2 | 97.1 | 0.908x | 7.586 | 8/9 |
| `nul_8_insert` | 432.3 | 493.2 | 0.877x | 58.056 | 8/9 |
| `nul_8_miss` | 14.1 | 14.5 | 0.971x | 0.357 | 6/9 |
| `nul_4096_insert` | 156876.9 | 177215.4 | 0.885x | 24822.420 | 8/9 |
| `nul_4096_grow` | 67718.0 | 75659.6 | 0.895x | 12614.271 | 6/9 |
| `nul_262144_insert` | 10119637.0 | 13190398.5 | 0.767x | 2901266.297 | 9/9 |

The candidate is rejected despite the no-op wins. No pooling, arbitrary variant,
placement tuning, backend investigation, or follow-up implementation was used to
hide the ordinary-path costs. There is no runtime-change PR or merge recommendation.

## Reproduce the archived experiment

Starting at the pinned baseline, preserve a baseline archive, apply
`bench/perf/string-empty-replace/exploratory/runtime.patch`, and build/preserve the
candidate archive from the same source path. Use an exit trap to restore original
source, the same pinned compiler and identical pure-helper IR, then build both
programs from `main.ms` (or both from `focused-controls.ms`) with the explicit tool
configuration above. Builds and native tests require a coordinated window.

Only during separate exclusive timing isolation:

```sh
taskset -c 0 python3 bench/perf/string-lines/compare.py \
    /tmp/before-replace /tmp/after-replace /tmp/replace-samples.csv --pairs 7 \
    --identity-file bench/perf/string-empty-replace/identities.json
```

Use nine pairs and `focused-identities.json` for the focused program pair. Keep
producer/identity failures fatal, retain every row and range, and report absolute
paired deltas/signs separately from ratios of medians. Never add an untracked
`target` directory or symlink to an evidence commit.
