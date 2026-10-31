# TOML control admission, 2026-10-31

Both byte-scan admission experiments are **rejected**. Production TOML code is
unchanged. The inline form improves a tiny cached-file round trip **2.591×** and
short errors **3.224–3.278×**, but broader controls confirmed a **1.75% slowdown**
for arrays of 128 tables. It was slower in 11 of 12 long paired trials while the
two identical-baseline medians differed by only 0.0044%. The earlier helper form
also incurred repeatable writer costs. Retain the large wins and regressions
together; neither candidate meets the campaign's regression rule.

This measures cached-file ingestion plus processing, including I/O. It is not
isolated parser timing or universal Rust parity. Rust remains faster on many
listed workloads. Do not subtract read timings. Source patches and behavior tests
are archived unapplied under variants; no optimization is shipped by this study.

## Source and behavioral contract

The forbidden set is exactly bytes 0–8, 11–31 and 127, excluding tab/LF. Valid UTF-8
continuations cannot equal those ASCII bytes. Ascending byte iteration preserves
the first rejected byte. Validate negative limits first and the original byte
budget second; normalize CRLF; obtain bytes; scan/locate an invalid control; then
construct Reader and allocate/parse. This preserves the existing rule that a later
invalid control precedes an earlier grammar error. C1 scalars remain admitted by
this precheck, as before.

The rejected inline implementation removes the one-use helper/Optional result and avoids
unused Reader construction on rejected input. That source simplification was
independently reviewed before trial; it was not instruction-placement tuning.

## Workload and observability

Base is main `81b804d58131224a00a10ebe3f3824e6c84313e1` (including #2139); candidate
core tree `bd1f5f153f6051cc0b71f0aaf9efbfca6a24f0f9`. Normal native/CLI builds
were repeated for baseline and candidate on that same tree, toggling only TOML's
admission code. All eight produced binary hashes match the independently measured
previous main-f900 cohort exactly: [rebuilt identities](results/2026-10-31/rebuilt-identities.json).
This supports reusing that cohort's long controls and RSS alongside the fresh
1,224-observation actual-main matrix. Native sources, Cargo inputs and toolchains
match; no security setting, check or compiler/backend option was changed.

Host: Linux x86_64 AMD EPYC 9V45, CPUs 0–4, shared host. Rust/Cargo 1.99.1
(`58cf8f9c3`), LLVM 23.1.1; Manuscript Release and pinned musl runtime. Rust
`toml=0.9.8` uses release opt-level 3, panic abort and the repository frame-pointer
flags. Rust controls use dynamic `toml::Value` string tables and natural owned
strings. There is no custom target-cpu or placement tuning.

The primary [file producer](file.ms) reads UTF-8 input **inside every measured
iteration**, parses and stringifies it, checks its complete output against setup,
and prints a validated count/checksum. Rust does the matching read/parse/stringify
and makes values observable with black_box. Input files, expected results and
printing are outside timing; cached-file reads, parsing, serialization and releases
are inside. Separate read-only and file-to-single-string-table writer controls
expose unrelated-path shifts without subtracting their medians.

An optional readiness marker is written after expected-output setup and before
timing. The external [probe](probe.py) replaces the input atomically after that
marker. Both producers must reject the changed value with status 1 and no timing
output. This verified the fresh-input dependency on the exact measured binaries.
The marker is absent in normal trials and never executes inside their timers.

All valid payloads are string tables: empty/tiny, 32/128/512 fields, quoted Unicode
and escapes, 32KiB/1MiB comments, 1MiB literal and roughly 1MiB Unicode. Rust decodes
all complete outputs and compares abstract values, allowing different valid TOML
quoting. Before/after Manuscript bytes must be identical. Six invalid-input cases
check exact errors, including initial/late controls in 1 MiB inputs; no unmatched
Rust diagnostic comparison is claimed. All outputs are guarded each iteration.

Each producer calibrates its own count to at least 50ms (up to one million calls);
**counts may differ**, and every actual count is retained. Twelve interleaved
trials use all six orders twice for three-label suites and balanced AB/BA for
errors. No local builds or other benchmarks run concurrently. Host noise remains
possible, so raw observations and A/A controls are retained.

## Inline candidate actual-main matrix

[Full samples](results/2026-10-31/actual-main/samples.jsonl),
[distributions](results/2026-10-31/actual-main/summary.json),
[environment](results/2026-10-31/actual-main/environment.json) and
[payload hashes](results/2026-10-31/actual-main/payloads-manifest.json) are retained.

Nanoseconds per complete cached-file operation. Before/after >1 is a gain;
after/Rust >1 is remaining overhead. Full median/MAD/min/max distributions are
retained. Rust errors are deliberately omitted.

| Operation | Case | Before ns | After ns | Rust ns | Before/after | After/Rust |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| roundtrip | empty | 5685.4 | 2132.6 | 1520.9 | 2.666× | 1.402× |
| roundtrip | tiny | 7901.7 | 3049.6 | 2045.3 | 2.591× | 1.491× |
| roundtrip | fields32 | 24384.5 | 19081.4 | 13891.2 | 1.278× | 1.374× |
| roundtrip | fields128 | 75197.2 | 68129.2 | 53844.2 | 1.104× | 1.265× |
| roundtrip | fields512 | 276689.0 | 270862.1 | 226387.4 | 1.022× | 1.196× |
| roundtrip | unicode16k | 190779.1 | 169423.1 | 40037.8 | 1.126× | 4.232× |
| roundtrip | escapes | 430534.8 | 409108.3 | 172477.1 | 1.052× | 2.372× |
| roundtrip | comment32k | 93761.3 | 72389.1 | 21412.4 | 1.295× | 3.381× |
| roundtrip | comment1m | 2751066.0 | 2233070.9 | 629027.6 | 1.232× | 3.550× |
| roundtrip | literal1m | 8184386.6 | 8055174.8 | 1849036.2 | 1.016× | 4.356× |
| roundtrip | unicode1m | 11759589.2 | 11074902.5 | 2414274.5 | 1.062× | 4.587× |
| error | zero | 7450.3 | 2305.1 | — | 3.232× | — |
| error | unicode | 7600.1 | 2357.3 | — | 3.224× | — |
| error | crlf-bare-cr | 7862.3 | 2398.9 | — | 3.278× | — |
| error | syntax-first | 7502.0 | 2324.4 | — | 3.227× | — |
| error | early1m | 109195.6 | 101100.0 | — | 1.080× | — |
| error | late1m | 2723905.2 | 2551142.4 | — | 1.068× | — |
| writer | empty | 2337.5 | 2293.3 | 1487.0 | 1.019× | 1.542× |
| writer | tiny | 2499.2 | 2482.1 | 1643.6 | 1.007× | 1.510× |
| writer | common | 2855.1 | 2856.1 | 1797.4 | 1.000× | 1.589× |
| writer | ascii16k | 87583.4 | 88194.4 | 24484.9 | 0.993× | 3.602× |
| writer | unicode16k | 123813.3 | 126030.3 | 26940.6 | 0.982× | 4.678× |
| writer | sparse | 86643.0 | 86964.0 | 25702.2 | 0.996× | 3.384× |
| writer | dense | 185959.5 | 186683.2 | 137343.2 | 0.996× | 1.359× |
| writer | mixed | 135391.0 | 134416.1 | 22254.2 | 1.007× | 6.040× |
| read | empty | 2068.4 | 2065.3 | 1421.7 | 1.001× | 1.453× |
| read | tiny | 2252.1 | 2237.7 | 1430.8 | 1.006× | 1.564× |
| read | fields32 | 2298.0 | 2310.9 | 1486.7 | 0.994× | 1.554× |
| read | fields128 | 2588.8 | 2558.1 | 1606.5 | 1.012× | 1.592× |
| read | fields512 | 3402.1 | 3372.6 | 2018.3 | 1.009× | 1.671× |
| read | unicode16k | 7042.8 | 7043.9 | 6767.0 | 1.000× | 1.041× |
| read | escapes | 9586.1 | 9625.8 | 6212.0 | 0.996× | 1.550× |
| read | comment32k | 4583.6 | 4630.1 | 2724.8 | 0.990× | 1.699× |
| read | comment1m | 88237.4 | 88280.4 | 52192.7 | 1.000× | 1.691× |
| read | literal1m | 88815.6 | 89118.8 | 53504.7 | 0.997× | 1.666× |
| read | unicode1m | 318645.4 | 322811.7 | 360655.8 | 0.987× | 0.895× |

The fresh matrix covers 396 roundtrip, 144 error, 288 writer and 396 read observations.
The [long writer A/A controls](results/2026-10-31/inline-writer-long/summary.json)
use about 700ms baseline processes. All three writer labels (baseline A,
baseline B and candidate) use the **same binary SHA-256**, as do before/after
read-only controls. Their observed label differences are A/A variation:
empty 2271/2278→2291 ns and tiny 2456/2461→2476 ns. Paired median differences
are 12.2/9.9 ns, candidate slower in 7/12 trials each; common is −0.9 ns, split
6/12. Unicode writing is 125310/125085→124099 ns. Retain these differences as
noise evidence; they do not demonstrate an algorithm-specific writer cost.
The earlier helper variant used different writer binaries and its reproducible
penalty remains a reason for rejection. This is not a claim that all timings
are identical.

[Whole-process RSS](results/2026-10-31/inline-memory/samples.json) covers 150 unique
fresh-process measurements across nine tiny/large/error/writer/read cases. Parser
roundtrip medians fall by 728 KiB on the listed cases; large error cases fall by 908 KiB.
Writer/read medians are unchanged. These include setup, I/O and teardown; they are
not allocation counts, and no mechanism is inferred from RSS alone.

## Structural discovery and rejection

The [broader pass](results/2026-10-31/structure-discovery/summary.json) covers nine
valid shapes: nested tables at depths 8/32, arrays of 1,024 strings and integers,
one array of 128 tables, shared dotted keys, Unicode keys, an empty key and a long
multiline string. All Rust abstract-value and exact before/after output checks
pass; blocked cases are an empty list. Six balanced three-label trials produce
162 observations, using the same exact binaries pinned above.

Arrays of tables lost about 1.48% in that pass, so a prespecified longer A/A
confirmation used twelve trials at about 700ms per baseline process. The
[36 retained observations](results/2026-10-31/structure-tables-long/samples.jsonl)
give baseline A/B medians 135650.55/135656.48 ns and candidate 138036.28 ns:
**+1.75%** versus mean baseline medians. Paired candidate-minus-mean-baselines
has median +1870 ns and is positive in 11/12 trials. Baseline MADs are 844/897 ns,
candidate MAD 437 ns. Ranges overlap, but the repeated direction and stable A/A
medians establish an actionable protected-shape regression. Do not dismiss it
because other cases improve more or because some individual ranges overlap.

The inline candidate is rejected and the production source restored. No third
placement variant or excluded backend/lifetime investigation was attempted.
[Original structural driver](variants/structure-discovery.py.txt), full payloads,
calibration counts, hashes and long-run provenance are retained. The driver was
run from .artifacts/control-scan in this worktree; it intentionally stops on
changed valid outputs and records invalid/unsupported cases separately.
The exact candidate patch against 81b is
[archived](variants/inline-scan-81b.patch), as are the four baseline-passing
[behavior tests](variants/toml-controls.ms.txt). These are evidence, not active
production/test-suite changes. Reapply them only for a future matched experiment.

## Retained rejected and exploratory work

The initial one-use control_offset helper also improved parsing but was held after
[long A/A writer controls](results/2026-10-31/helper-writer-long/summary.json)
showed reproducible costs of about 1.5–2.4%: paired candidate costs 36.9 ns empty
(12/12 slower), 30.5 ns tiny(11/12), 47.2 ns common(10/12). Overlapping ranges did
not erase that signal. Its full 1,224 observations, 144 long observations and 150 RSS
records remain separate. The [unapplied helper patch](variants/helper-scan-f900.patch)
reconstructs that candidate against f900; zero-context patches use git apply
--unidiff-zero. The inline version has a real error-path simplification but its later arrays-of-tables
regression independently requires rejection.

Earlier invariant-text loops reported much larger apparent factors (including
66× empty and 123× short errors). Whole-output guards and printed checksums prove
observable results, but do not source-prove recomputation of invariant parsing on
every iteration. Those [guarded observations](results/2026-10-31/guarded-discovery/summary.json)
are **discovery only** and support no isolated-parser/Rust performance claim.
No excluded compiler/backend investigation was used to resolve that uncertainty;
the primary workload instead reads fresh external input per iteration.

The first cached-file Rust read control held an unnecessary setup string copy.
Its [source snapshot](variants/read-setup-copy.rs.txt) and complete matrix remain
in file-discovery; the corrected Rust read control is used for file-final and later
cohorts. Historical source snapshots/patches preserve old source hashes. A failed
failure-probe attempt lacked rustc on PATH and stopped before bad producers ran;
it is retained as explicitly inconclusive. Corrected probes require an invocation
marker, the intended error reason and no final summary for all three bad producers.

Payloads are losslessly gzip-compressed JSON: each original filename maps to exact
UTF-8 bytes, decoded byte count and SHA-256. Manifests also hash compressed and
uncompressed bundles. Every entry was round-tripped against its original bytes.
Raw timing/RSS records and environments remain directly readable. Build targets
are ignored; a local accidental staging was removed before any publication.

## Validation and limitations

Passed on the measured 81b main: four archived source tests cover every ASCII byte/C1 scalar;
first Unicode-scalar location and CRLF/bare CR; byte/value/depth and syntax error
precedence; and offset boundaries 0, 1, 31, 32, 127, 128, 129, 255, 256, 1024. They also pass
on the untouched baseline compiler. Existing 14 TOML source tests, four quoting tests
and 12 corpus TOML tests pass (34 source tests total).

Workspace/control Rust formatting, control Clippy with warnings denied, repository
checks, license freshness, Python syntax and whitespace checks pass. Three
controlled bad producers are rejected for the intended failure reason without a
summary; external-input probes verify both measured producers. Independent review
checked semantics, identities, distributions, the 37 new structural payloads and
exact reconstruction of the archived candidate. No production or active-test
diff remains versus main.
No GitHub approval is submitted on the user's behalf.

Full workspace/native conformance, backend, ownership/cleanup, HTTP, Debug JSON and
Windows investigations were not run under campaign exclusions. Required CI remains
enabled. Later combined-main replay is required for retained production changes after other
pending native changes, including JSON #2126, merge. This rejected experiment
does not establish clean status for other TOML/YAML/JSON shapes or error policies.

## Replay

Use two matched worktrees on the pinned base, toggling only this admission change.
In each run cargo xtask runtime then cargo build --release --locked -p ms-cli.
Build file.ms, file-error.ms, file-writer.ms and read.ms with --build-type Release.
Build the standalone Rust control with its committed lockfile. Use a writable
XDG_CACHE_HOME if required; never bypass archive freshness checks.

```sh
cargo build --release --locked --manifest-path bench/perf/toml-control-scan/rust/Cargo.toml
python3 bench/perf/toml-control-scan/file-run.py --before /absolute/file-before --after /absolute/file-after --rust /absolute/rust/file --error-before /absolute/error-before --error-after /absolute/error-after --writer-before /absolute/writer-before --writer-after /absolute/writer-after --read-before /absolute/read-before --read-after /absolute/read-after --rust-writer /absolute/rust/file-writer --rust-read /absolute/rust/read --output /fresh/full --revision PINNED_BASE
python3 bench/perf/toml-control-scan/probe.py --before /absolute/file-before --after /absolute/file-after --output /absolute/probe.json
python3 bench/perf/toml-control-scan/fail-probes.py --environment /fresh/full/environment.json --output /absolute/failure-probes.json
python3 bench/perf/toml-control-scan/focused.py --environment /fresh/full/environment.json --summary /fresh/full/summary.json --inputs /fresh/full --output /fresh/long --operation writer --cases empty tiny common unicode16k
cc -O2 bench/perf/representative/rss.c -o /absolute/rss
python3 bench/perf/toml-control-scan/memory.py --environment /fresh/full/environment.json --inputs /fresh/full --rss /absolute/rss --output /fresh/memory
python3 bench/perf/toml-control-scan/pack.py --source /fresh/full --output /fresh/retained
```

The driver records actual commands and fails closed on producer failure, changed
values/bytes, incorrect diagnostics/counts/checksums or incomplete observations.
Keep full old/new distributions, including unfavorable controls, for each replay.
