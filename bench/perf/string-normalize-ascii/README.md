# ASCII identity normalization and lazy Unicode input

Candidate on pinned baseline `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.
Focused correctness, recorded comparisons, and local gate evidence are complete.
The failed canonical conformance invocation and successful separate controlled
replay are both retained below. Final immutable review, required CI, PR, and
publication remain pending; this report is not a merge approval.

## Final code and observable contract

All ASCII scalars, including NUL, controls, and DEL, are unchanged by NFC, NFD,
NFKC, and NFKD. After the existing negative-budget and form validation, empty
input uses the existing empty constructor. A nonempty ASCII input checks its
byte length against the existing output budget and calls existing `from_bytes`.
This skips the whole Unicode identity algorithm and intermediate input buffer.
A non-ASCII first byte avoids a failed full ASCII scan. Later Unicode pays for
a failed scan and then takes the Unicode path.

For Unicode, safe `core::iter::from_fn` supplies the identical existing
`utf8::decode`/`char::from_u32` fallback sequence directly to UnicodeNormalization,
replacing the eager input `Vec<char>`. Output encoding, push/budget arithmetic,
status and error identity, selectors, and `from_buf` are unchanged. No constructor,
allocator, cache, ownership, cleanup, or language iterator machinery changes.

Malformed input retains one U+FFFD per invalid decoded byte; a literal U+FFFD is
preserved. Error outputs remain untouched. No bounded-prefix-decoding or bounded
normalizer-buffer claim is made: a normalizer can look ahead through a complete
combining segment even when an output budget will fail.

## Checks and build configuration

Both runtime archives came from this same normalizer worktree path. The baseline
was temporarily restored from the named commit with an exit trap protecting the
candidate. V1 reused that saved matched baseline and built its candidate here.
The unchanged pinned compiler is SHA-256
`cd158b8ca24e62776ba38aa8b774e57f4dd1434346d2edc7569211e7b848c0fc`.
Pure helper files match byte for byte, SHA-256
`8315efc0c1ae0b87ff80185ee282e4ede97e82afa6ecfe1825fe296549bc46ef`.

All 22 Rust string tests pass, including all 128 ASCII values, literal U+FFFD,
malformed/truncated/overlong/surrogate/out-of-range bytes, ASCII-first invalid
fallback, and exact/zero/exceeded budgets with exact output bytes. Three original
source tests plus two ASCII-extension tests pass in both explicit Release and
Debug; both existing typed-normalization tests pass in each profile too.
Frontend/format checks passed before measurement. The final runtime rebuild,
Rust formatting and workspace clippy (`--workspace --all-targets -- -D warnings`)
also pass. Focused logs are under [logs](logs/); final gate records are under
[checks](checks/). Repository checks passed again under root orchestration with a unique confirmed
log. The original `make conform` failed. A separate serial pinned-input strict
replay passed all 2393 selected cases (1603 check, 531 run, 259 test), with zero
failed, expected-failed, unexpected-passed or unrecorded outcomes. Its completed
log and report are retained and hashed; this does not turn the make invocation
into a pass.
Workspace-wide nextest was not rerun because the known excluded
`ms-build::debug_artifacts` missing-executable path is outside this lane.
Normal required CI remains a gate; no test or allowlist was changed or skipped
to obtain a pass.

Normal builds requested Release with the explicit cached `MS_LLVM_TOOLS` path.
Verbatim public CLI JSON and companion metadata are retained; companion copies
use ordinary names under [build-metadata](build-metadata/). Both full and
focused companion files label the programs **Cranelift, Release**. Effective
optimization beyond that metadata is unverified; no backend, trace, assembly,
or code-placement investigation occurred.

The focused pair's first build omitted the supplied environment and failed while
using a read-only default cache, before either executable existed. Those failure
logs are retained. Rebuilding with the supplied environment succeeded. This was
resolved preparation failure, with no timing data from the failed attempt.

## Measured workload and method

Recorded 2026-10-29 on the coordinated Intel Xeon Platinum 8573C Linux VM with
five exposed CPUs, Linux 6.18.55 and Rust 1.99.1. Runner and producers used CPU 0;
there were no concurrent builds, tests, or other timed work. Other platforms and
application frequencies were not measured.

The full program preserves every original 84-case control and adds all four
forms with Unicode before/after 4 KiB and 1 MiB ASCII prefixes: 100 fixed
identities. Literal `éﬁ` checks form-specific decomposition and compatibility
mapping; expected block byte lengths are 5/6/4/5. Every operation validates exact
output or the expected domain error before contributing a checked checksum.
Setup, expected construction, checked warm-up, compilation, process startup,
and printing are outside timing. Normalization, full validation and result
release are included. These are end-to-end operation timings, not isolated
Unicode-algorithm costs. No expected output calls the operation being measured.

All producer/identity guards passed. [samples.csv](samples.csv) retains all 1400
rows from 100 cases, two variants and seven alternating pairs. [summary.csv](summary.csv)
retains every median and min/max range. [paired-samples.csv](paired-samples.csv)
retains all 700 per-pair normalized times/deltas/ratios; [paired.csv](paired.csv)
retains paired signs and distributions separately from ratio-of-medians.

The full matrix improves 88 medians. Representative results follow; all values
are ns per operation including validation, and the full distributions remain
available. Large ratios are workload-specific, not precise cross-machine claims.

| Case | Before median | After median | After range | Ratio |
| --- | ---: | ---: | --- | ---: |
| `empty_NFC_full` | 26.1 | 13.7 | 11.4–16.3 | 1.909x |
| `one_ascii_NFC_full` | 96.1 | 16.3 | 14.6–36.9 | 5.904x |
| `ascii_controls_NFC_full` | 303.1 | 22.3 | 17.2–56.0 | 13.612x |
| `ascii_scale_4096_NFC_full` | 669498.8 | 1835.5 | 1437.7–4374.8 | 364.747x |
| `ascii_scale_65536_NFC_full` | 11383739.9 | 40626.3 | 33891.4–144314.3 | 280.206x |
| `compose_NFC_full` | 158.4 | 114.0 | 99.3–136.8 | 1.389x |
| `early_unicode_1048576_NFD` | 23058444.9 | 21990059.6 | 21006361.6–57177403.0 | 1.049x |
| `late_unicode_1048576_NFD` | 25186349.9 | 25114056.0 | 20186487.5–34827885.2 | 1.003x |

Every full-matrix median regression follows. Paired delta is the median
candidate-minus-baseline difference; a negative delta favors the candidate.
The ratio column is ratio-of-medians, not the median paired ratio.

| Case | Before median | After median | Ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `canonical_scale_4096_NFD_full` | 217214.1 | 221292.9 | 0.982x | -5345.832 | 2/7 |
| `compatibility_scale_4096_NFD_full` | 232396.7 | 250995.5 | 0.926x | -28763.004 | 2/7 |
| `compatibility_scale_65536_NFD_full` | 3881550.1 | 4170529.5 | 0.931x | 528452.188 | 5/7 |
| `combining_segment_NFKC_full` | 19823.5 | 19833.4 | 0.999x | 1889.453 | 4/7 |
| `budget_NFC_exact` | 254653.3 | 259728.6 | 0.980x | 7818.660 | 4/7 |
| `budget_NFC_exceeded` | 271544.5 | 305582.9 | 0.889x | 22328.332 | 4/7 |
| `negative_NFC` | 5.4 | 7.4 | 0.736x | 1.452 | 5/7 |
| `budget_NFD_exact` | 216826.9 | 263788.1 | 0.822x | 29138.664 | 4/7 |
| `negative_NFD` | 5.8 | 5.9 | 0.979x | -0.293 | 2/7 |
| `budget_NFKC_exact` | 270370.9 | 290919.8 | 0.929x | -29578.516 | 3/7 |
| `negative_NFKC` | 6.3 | 6.7 | 0.944x | 0.339 | 5/7 |
| `late_unicode_4096_NFKC` | 128172.0 | 129421.2 | 0.990x | -17026.773 | 3/7 |

## One bounded focused comparison

The unchanged runtime was compared using 30 selected cases and nine alternating
pairs: all negative-budget and invalid-form controls, all zero/exact/exceeded
budgets, the unfavorable Unicode/scaling medians and nearby counterparts, plus
empty/one-ASCII controls. Shorts use 5M operations, mid-size/combining cases 1024,
and large cases 64. The source and exact inventory are [focused-controls.ms](focused-controls.ms)
and [focused-identities.json](focused-identities.json).

All checked warm-ups, producer exits, exact outputs/errors and identity guards
passed. [focused-samples.csv](focused-samples.csv) retains all 540 rows;
[focused-summary.csv](focused-summary.csv) every median/range;
[focused-paired-samples.csv](focused-paired-samples.csv) all 270 paired observations;
and [focused-paired.csv](focused-paired.csv) the separate paired statistics.
Focused processes omit preceding full-matrix workloads and allocation phases.
They do not replace, pool with, or erase the original 100-case observations.

The complete focused table follows, in ns per operation including validation:

| Case | Before median | After median | Ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `negative_NFC` | 5.4 | 6.7 | 0.805x | 0.857 | 6/9 |
| `negative_NFD` | 5.5 | 5.6 | 0.977x | 0.290 | 7/9 |
| `negative_NFKC` | 5.6 | 5.5 | 1.017x | -0.486 | 4/9 |
| `negative_NFKD` | 5.8 | 5.4 | 1.078x | -0.012 | 4/9 |
| `invalid_lowercase` | 6.6 | 6.8 | 0.969x | 0.472 | 6/9 |
| `invalid_unknown` | 6.8 | 7.2 | 0.949x | -0.260 | 3/9 |
| `invalid_nul` | 6.7 | 7.1 | 0.939x | 0.418 | 5/9 |
| `invalid_negative` | 5.2 | 6.1 | 0.859x | 0.361 | 5/9 |
| `budget_NFC_zero` | 26404.7 | 64.5 | 409.480x | -26339.796 | 0/9 |
| `budget_NFC_exact` | 208575.5 | 204911.5 | 1.018x | 1362.128 | 5/9 |
| `budget_NFC_exceeded` | 212148.7 | 205873.6 | 1.030x | 1210.702 | 5/9 |
| `budget_NFD_zero` | 22601.9 | 21.1 | 1071.447x | -22580.782 | 0/9 |
| `budget_NFD_exact` | 190958.2 | 181857.4 | 1.050x | -15281.143 | 3/9 |
| `budget_NFD_exceeded` | 186382.2 | 169084.5 | 1.102x | -16814.741 | 2/9 |
| `budget_NFKC_zero` | 24026.2 | 66.1 | 363.291x | -23962.156 | 0/9 |
| `budget_NFKC_exact` | 221184.1 | 222578.7 | 0.994x | 3723.282 | 5/9 |
| `budget_NFKC_exceeded` | 234018.1 | 212661.1 | 1.100x | -3508.820 | 4/9 |
| `budget_NFKD_zero` | 25371.4 | 20.8 | 1220.648x | -25314.791 | 0/9 |
| `budget_NFKD_exact` | 214406.4 | 181409.6 | 1.182x | -7704.744 | 4/9 |
| `budget_NFKD_exceeded` | 204299.3 | 175546.5 | 1.164x | -6706.537 | 3/9 |
| `compatibility_scale_4096_NFD_full` | 222816.4 | 195166.0 | 1.142x | -14301.407 | 1/9 |
| `compatibility_scale_65536_NFD_full` | 3444087.5 | 3146457.3 | 1.095x | -232802.203 | 1/9 |
| `canonical_scale_4096_NFD_full` | 211213.8 | 168546.9 | 1.253x | -9238.046 | 0/9 |
| `combining_segment_NFKC_full` | 18961.3 | 16265.2 | 1.166x | -2786.368 | 3/9 |
| `canonical_scale_65536_NFD_full` | 3466954.3 | 2783268.8 | 1.246x | -318924.516 | 2/9 |
| `late_unicode_4096_NFKC` | 113158.7 | 109245.4 | 1.036x | -6526.660 | 3/9 |
| `early_unicode_1048576_NFD` | 24144256.1 | 17898223.7 | 1.349x | -3103610.328 | 1/9 |
| `late_unicode_1048576_NFD` | 21739841.6 | 19301895.0 | 1.126x | -2063203.234 | 2/9 |
| `empty_NFC_full` | 28.4 | 11.9 | 2.376x | -14.809 | 0/9 |
| `one_ascii_NFC_full` | 85.8 | 14.7 | 5.832x | -70.751 | 0/9 |

Of the 22 focused controls with valid text and nonnegative arguments, 21 medians
improve; this group includes expected `LimitExceeded` handling. NFD exact budget
changes 190.96→181.86 µs, with six of nine faster pairs; large compatibility NFD
changes 3.444→3.146 ms, with eight of nine faster pairs. Their original full-matrix
penalties (+21.66% and +7.44%) are preserved above and are not claimed as stable
costs. NFKC exact budget remains +0.63% by median, five of nine slower, with a
+3.723 µs paired median and a wide candidate range (206.98–3758.27 µs). This does
not establish a uniform or tail-latency improvement; all checked outliers remain.

## Proposed retention rationale and explicit tradeoff

The measured valid-input paths support progressing through the remaining gates:
ASCII avoids an identity algorithm, Unicode decoding loses an intermediate input
buffer, and the focused material Unicode median penalties do not repeat.
Independent performance review supported the local gates and final immutable
review with the costs below disclosed. Final acceptance is not decided by this implementation report.

Invalid arguments remain an unfavorable tradeoff. Negative NFC repeats a
5.400→6.709 ns median change (+1.308 ns, +24.23%), six of nine slower pairs and
a +0.857 ns paired median. The full comparison was +1.953 ns (+35.88%), five of
seven slower and +1.452 ns paired median. Negative NFD is +0.130 ns focused,
seven of nine slower; invalid lowercase/NUL/negative controls have focused median
increases of +0.212/+0.435/+0.863 ns. Some other invalid-path medians reverse.
These costs are reported explicitly rather than rounded away or called resolved.
Negative budgets and invalid spellings represent rejected arguments; their
frequency in real applications was not measured. A validation-heavy workload may
weight those costs differently. There is no universal-speed or global all-clear
claim and no new variant or placement experiment is proposed to hide them.

## Separate superseded experiment

[../string-normalize-stream](../string-normalize-stream/) preserves the earlier
lazy-decoder-only source, exact runtime patch, 84-case 1176-row comparison, paired
data, build metadata and correctness logs. Its 11 median regressions remain
visible. Its 24-case focused source/inventory are prepared but **unbuilt and
unrun**. The added ASCII identity path was a new causal mechanism, not a repeat
or reinterpretation of that initial experiment. V0 source/archive/helper/program
snapshots remain under `/tmp/string-round2/normalize-{before,after}` and the extra
`normalize-v0` snapshot. No v0 data is pooled into the final distributions.

## Reproduce and pending gates

[builds.json](builds.json) records source/patch/compiler/archive/helper/program,
runner, fixture, public metadata and all data/log hashes. Build both runtime
versions from this same source path, preserving the candidate via an exit trap,
and keep pure helpers identical. Pinned artifacts are in
`/tmp/string-round2/normalize-ascii-{before,after}`. Source the provided environment
before normal builds; the committed shared runner preserves its default line
inventory and adds strict `--identity-file` validation.

```sh
. /tmp/string-env.sh
MS_RT_LIB=/tmp/string-round2/normalize-ascii-before/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /tmp/string-round2/ms build     bench/perf/string-normalize-ascii/main.ms --build-type Release     -o /tmp/string-round2/normalize-ascii-before/program --json
MS_RT_LIB=/tmp/string-round2/normalize-ascii-after/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /tmp/string-round2/ms build     bench/perf/string-normalize-ascii/main.ms --build-type Release     -o /tmp/string-round2/normalize-ascii-after/program --json
taskset -c 0 python3 bench/perf/string-lines/compare.py     /tmp/string-round2/normalize-ascii-before/program     /tmp/string-round2/normalize-ascii-after/program     bench/perf/string-normalize-ascii/samples.csv --pairs 7     --identity-file bench/perf/string-normalize-ascii/identities.json
```

Build `focused-controls.ms` similarly to `focused-program`, then use `--pairs 9`
and `focused-identities.json` for the focused comparison. Do not run while another
coordinated build/test/timing job is active. No CI timing threshold is added.

Freshness: root checked current main
`4b056af1ef8cbe894e74d912776c4bf1005ec1d5` against the measurement baseline;
string/UTF-8/ABI/Cargo/toolchain/guidance paths are unchanged, so no rebase was
requested. Final Rust formatting, workspace clippy, and confirmed repository checks
pass. The separate pinned serial strict replay passes all 2393 selected cases.
Final immutable artifact review, normal required CI, and root-managed
PR/publication remain pending. Workspace nextest is explicitly unrun in this
lane, rather than being represented by focused tests. The untracked shared
`target` symlink is excluded from the commit.

Root owns the authoritative gate results after a command-handoff overlap. This
agent's duplicate session was terminated (exit 130), with no live native children;
no gate conclusion is inferred from the interrupted invocation. The publication
draft is kept outside the repository in `/tmp/string-round2/normalization-pr-body.md`.

## Local conformance gate failure and controlled replay

The original root-owned `make conform` exited **2**, with 1608 passing and 785
native-build failures among 2393 selected outcomes. The gate-handoff overlap left
an original mixed log containing strip file-truncation errors. The generated
target runtime archive SHA-256 was
`f314c720acf628547d9e3c3fe7750acaab9be18786aa20c3dfc3a684583089c3`, differing
from the validated candidate
`3b3c1b8bdc8dc97ce207ddf1750ca2e6d1c66e134fba48488bbbdb7baa3b014e`.
[checks/conform-failed-report.md](checks/conform-failed-report.md) and
[checks/conform-failed-input.json](checks/conform-failed-input.json) preserve the
failure and input hashes. This remains a **failed `make conform`**, not a source
fix or a CI pass. No backend, strip-code, or compiler investigation/repair was
performed in this lane.

Root restored the validated runtime/helper input and started a **separate serial
strict replay**, using the existing corpus runner with pinned Release compiler
`/tmp/string-round2/ms` and explicit `MS_RT_LIB` pointing to the validated 3b3c
archive. It selects the same 2393 cases, run/check/test phases, strict expectations,
allowlist and shard. This replay exited **0**: **2393/2393 passed** (1603 check,
531 run, 259 test), with zero failed, expected-failed, unexpected-passed or
unrecorded outcomes. The completed [log](checks/conform-pinned.log) and
[report](checks/conform-pinned-report.md) preserve that separate result. The
original make invocation remains failed. Normal required CI remains mandatory;
this controlled local replay is not a CI pass or merge approval.

## Evidence byte preservation

The full staged whitespace check flags the three saved unified patches (required
single-space blank context), verbatim conformance stderr in `checks/conform.log`
and `checks/conform-failed-report.md`, and generated report final blank lines in
`checks/conform-failed-report.md` and `checks/conform-pinned-report.md`. Those
immutable evidence bytes and hashes are preserved. A scoped whitespace check
excluding exactly those six evidence files passes for all authored source,
documentation, runner, matrices and other records. No generated output is edited
to obtain that check result.
