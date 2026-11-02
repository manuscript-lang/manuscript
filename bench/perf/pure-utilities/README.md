# Pure utility comparisons

This suite checks POSIX lexical path components/normalization and pure URL
component codecs/parsing. It performs no filesystem operations or network calls.
The Rust path controls preserve Manuscript's dotfile, trailing-separator and
directory-spelling rules; substituting `std::path` would change the workload.
The URL parse control calls the same `ms_std_url::parse` implementation, so it is
an attribution control, not an independent parser comparison.

## Protocol

The initial discovery baseline is main
`09e0eb7e66b0437d257dd5e2702855a158c35739`. Rust/Cargo 1.99.1, Linux x86-64,
AMD EPYC 9V74, five visible CPUs/four-core cgroup, 16 GiB. Producer launchers and
children use CPU 0. This shared VM does not provide isolated-core guarantees.
No local build, test or other benchmark runs during timing.

MS producers use explicit Release builds, LLVM tools 23.1.1 selected by the
repository's pinned linker/toolchain files, the same fixed compiler, and
separately supplied musl release native archives. Rust controls use optimized
release with checked workload arithmetic and native release dependency profiles.
Metadata records revisions, source/toolchain/lock and binary hashes, backend
selectors, machine, affinity, case order and whole-process CPU deltas.

Setup and expected records precede timers. Every output field or concrete
`InvalidData` result is checked inside timing and contributes to a checksum.
Rust inputs and output checksums pass through `black_box`. Measurements therefore include
operation, exact validation, output destruction and checksum work. No producer
uses Debug or JSON rendering. The Python recorder uses JSONL after producer
timers; its output is losslessly compressed for storage.

There are 72 path cases: 24 tiny/common/Unicode/long/adversarial inputs, each
measuring extension, all five owned parse fields, or lexical normalization.
The final suite has 79 URL cases: seven encodes, 33 successful decodes, 20
malformed decodes, seven successful parses and twelve parse errors. The initial
discovery had 44; seven sparse/prefix controls and 28 predeclared size-boundary
controls were added before final replay. Cases include long
safe/escaped text, leading/trailing invalid percent escapes and invalid UTF-8.
The full case inventory, inputs and expected fields are recorded in each file.
The argv/TSV transport excludes raw NUL and invalid UTF-8 inputs and decoded
control delimiters; native differential tests separately cover NUL text.

One retained warmup trial precedes measured trials. Cases rotate, and producer
orders cycle through every permutation: 12 repeats balance three producers;
24 balance four. No observations are discarded. Compare paired ratios and A/A
before interpreting a small difference. Rust encode reserves up to three times
input length; this tradeoff is not a proposed production change. Rust decode
uses a streaming reference; literal `+` stays plus and invalid UTF-8 fails.

## Reproduce

Build each pinned native archive in its own worktree using `cargo xtask runtime`.
Use one compiler for both MS producers, overriding `MS_RT_LIB` for each archive:

```sh
MS_RT_LIB=/absolute/before.a /absolute/ms build bench/perf/pure-utilities/path.ms --build-type Release -o /tmp/path-before
MS_RT_LIB=/absolute/after.a /absolute/ms build bench/perf/pure-utilities/path.ms --build-type Release -o /tmp/path-after
cargo build --release --locked --manifest-path bench/perf/pure-utilities/rust/Cargo.toml
python3 bench/perf/pure-utilities/repeat.py --kind path \
  --producer before=/tmp/path-before --producer after=/tmp/path-after \
  --producer rust=$PWD/bench/perf/pure-utilities/rust/target/release/pure-utilities-control::path-rust \
  --producer before-AA=/tmp/path-before --repeats 24 > /tmp/path.jsonl
python3 bench/perf/pure-utilities/validate.py /tmp/path.jsonl
```

Use `url.ms`, `--kind url` and `::url-rust` for URL cases. Optional
`::path-native`/`::url-native` modes directly exercise the same native libraries.
Run the validator on any plain or gzipped retained JSONL; it checks complete
trial sets, balanced positions, exact fields/errors/checksums and every summary.

Historical discovery sources lived under `.artifacts/pure-utilities`; their
recorded hashes and filenames remain intact. Publication relocates those sources
and adjusts only root/dependency paths and the introductory runner docstring.
The final candidate measurements use the published source paths. The final Rust
adapter selects path/URL and implementation outside timing and retains unused
empty fields across iterations, matching the MS producers. Historical discovery
and components-only runs used a wrapper that rebuilt those empty fields and
checked invariant mode strings inside timing; their Rust ratios are superseded.
Their MS before/after comparisons remain valid and are retained.

## Final path change, 2026-10-31

Fresh main `41304943d677b2f276c3073addbac41faa4c0772` contains the earlier
calendar fixes and the other campaign changes merged at replay time. Rebuild
its compiler/native archive, apply only the final path patch, and rebuild the
candidate archive. The same fresh compiler builds both producers. All 72 path
cases and 79 URL controls pass warmup plus 24 fully balanced trials: **15,100
producer invocations**. Native allocation controls separately pass **1,000
observations across 125 cases**. All source/binary/archive hashes are retained in
[identities.json](results/identities.json), headers and the lossless manifest.

The retained path change avoids building all five parse fields for an extension,
replaces a leading-dot basename's full dot count with its already-known extension
length, and removes two POSIX normalization identity copies. The original parse
input copy and scalar reverse extension helper remain intact after rejected
copy/scan changes regressed long-basename parsing. No URL production code changes.

| Workload | Before ns/op | After ns/op | Paired after/before | Paired after/Rust |
| --- | ---: | ---: | ---: | ---: |
| Common extension |124.56|54.05|0.441|0.123|
| Long dotted extension |8,071.45|283.01|0.035|0.433|
| Common parse |129.44|126.63|0.992|0.663|
| Long dotted parse |8,683.38|1,046.23|0.120|0.924|
| Common normalize |172.60|149.69|0.875|0.324|
| Long-basename normalize |948.80|791.19|0.834|0.968|
| Long-directory normalize |5,574.97|5,073.53|0.917|0.952|

Times are separate medians; ratios are medians of same-trial pairs, so dividing
the displayed times need not reproduce them. Every extension paired median is
0.035–0.973 and every normalize median 0.777–0.986. These workload/validation
comparisons do not establish intrinsic language or universal Rust superiority.

All adverse parse paired medians remain disclosed: empty 1.026, dot 1.031,
long basename 1.053, parent-dot 1.005, relative-empty 1.011, long extensionless 1.004,
only-slashes 1.014. Long-basename A/A is 1.039 and its paired interquartile range
0.971–1.134. A longer, position-balanced three-case confirmation retains 225 more
invocations, with 4 million base iterations:

| Parse control | Paired after/before | A/A | Faster/24 |
| --- | ---: | ---: | ---: |
| Empty |1.020|1.007|5|
| Dot |1.001|1.013|12|
| Long basename |1.004|1.008|11|

Empty parsing has a **0.771 ns median paired increase**, slower in 19/24 long
pairs; it is not claimed flat. Dot and long-basename confirmation does not
establish a material regression. Independent review supports retention with
that marginal empty-input cost disclosed. Remaining parse/Rust gaps include
long directory 1.761, long extensionless 1.963 and long dotfile 2.058.

[Native allocation probe](allocation-probe.md): common extension falls from
seven allocations/62 requested bytes to one/three; nonempty normalize loses two
allocations. Long-basename normalize falls from six/16,484 bytes to four/8,278.
These are direct native helper counters, not MS runtime allocation counts or RSS.
Parse allocation counts remain unchanged. All 53 decode allocation cases are
identical before/after. The first stale executable replay is preserved as
**invalid provenance**, excluded from claims; corrected and fresh replays pass.

## Initial rejected candidates and URL limits at main 413

| Candidate | Blocking evidence |
| --- | --- |
| Parse copy removal plus reverse-scan replacement | Components-only and combined runs both doubled long-basename parse in all 24 pairs. |
| Streaming component decoder | Malformed early/late escapes changed zero allocations to one 4,003-byte allocation; rejected before CPU timing. Dense valid input already reserved full input length in both implementations. |
| No-percent shortcut | Long safe improves to 0.226, but common mixed decoding 1.147, Unicode 1.077 and early malformed 1.245; full 44-case controls retained. |
| Dedicated preflight decoder | Preserves zero-allocation malformed rejection; focused Unicode 1.248, dense escapes 1.716 and valid-prefix errors 1.961 regress. |
| Bounded preflight decoder | Retains large gains but common safe 1.089, plus 1.079 and mixed 1.081 against nearly flat A/A. Safe/plus slower 11/12; mixed 12/12. |

No rejected candidate is active. The final 79-case URL replay uses byte-identical
before/after/A/A MS executables. Their paired medians span 0.964–1.059; those
variations cannot be attributed to path code. URL source is unchanged and known
Rust gaps remain: long safe 4.027, sparse 2.632, tail escape 7.584, raw Unicode 6.330,
late malformed 3.003 and late invalid UTF-8 7.071. The streaming Rust control can
allocate before rejecting malformed escapes; the native decoder does not. That
allocation tradeoff remains explicit. No eligible URL fix was demonstrated.

All 43,308 archived observations, including 720 invalid-provenance observations,
are losslessly retained. The manifest distinguishes timing, allocation and
invalid provenance; no adverse sample is discarded. Source snapshots include
every rejected implementation and exact historical recorder. To reproduce an
old candidate, use an isolated worktree at its recorded revision and restore the
matching snapshot to the recorded crate/runner path before building. Historical
snapshots are evidence and are not live implementation modules.

```sh
python3 bench/perf/pure-utilities/validate.py --manifest bench/perf/pure-utilities/results/manifest.json
```

The validator checks complete trials, positions, fields/errors, checksums,
summaries, native counters, raw/compressed hashes and recorded source identities.
It explicitly excludes the stale allocation association from valid evidence.

Final source validation: two exact POSIX native tests, three called MS tests in
Debug/Release, all 151 case smoke controls, workspace/all-target Clippy with
warnings denied, workspace/standalone Rust formatting and Clippy, source
formatting, repository invariants and complete artifact validation pass.
Full workspace execution, broad conformance and non-Linux performance were not
run locally under campaign scope; normal required CI remains unchanged. Known
Rust gaps are unresolved, not a parity or globally clean claim. Actual merged
main replay remains a final follow-through step.

## Subsequent decoder work

The [direct byte-scan follow-up](url-component-scan.md) records a fifth decoder
candidate on merged main 28946f9, after the path fix landed. It keeps the earlier
measurements above intact, adds the malformed escape after an invalid-UTF-8
prefix, and records a separate full runtime replay. Compiler/source/executable
identities are explicit; these reports make no build-time claim.
