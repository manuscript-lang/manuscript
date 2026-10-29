# Regex result work, 2026-10-29

Baseline: `7e2e62357d5cebc1f144b6ee86f38da247cd2f52`. The comparison uses one
release-built compiler, identical benchmark source, and separately built baseline
and candidate native runtime archives. The changes are confined to
`ms-std-regex`; no compiler or backend change is involved.

The operations previously allocated capture bookkeeping for every `captures_all`
match, allocated and copied a temporary string for every template expansion,
looked up named-group indices that were already available, and collected captures
even for literal templates. The candidate reuses capture locations within one
successful collection, expands directly into the final string, uses group indices,
and lazily distinguishes literal templates from dollar expansions. Literal output
that cannot fit is rejected before appending it.

The span-selection algorithm, full-haystack matching context, strict budgets,
missing-group representation, named-group order, and template dialect are
unchanged. Capture scratch is allocated after match-count validation and only
when at least one match exists. The lazy template test avoids scanning a large
unused template when there are no matches.

## Method

Linux x86-64 6.18.55, Intel Xeon Platinum 8573C, five exposed CPUs, four-CPU
cgroup quota, 16 GiB memory limit. Rust 1.99.1
(`58cf8f9c3`, 2026-10-13); regex 1.13.1. `cargo xtask runtime` builds the static
`x86_64-unknown-linux-musl` runtime with Rust release optimization. Generated
programs explicitly use `MS_BACKEND=cranelift` with `ms bench`'s default Release
profile: optimized MIR and Cranelift speed optimization. The retained benchmark
JSON reports `build_type: "Release"`. These are not LLVM results.
The CLI's build sidecar currently hardcodes its backend field, so an explicit
backend setting establishes the identity here.

Seven paired process runs alternate before/after order. Each run takes three
timed samples per case after untimed setup and calibration/warmup. Measurement
uses `@std/bench.ms` inside the generated executable, excluding compilation,
compiler startup, process startup, regex compilation, and input preparation.
The driver is pinned to CPU 0; no other local builds or tests run during the
comparison. These are warm measurements on a shared VM, not cold-cache results.

Every capture row is compared with the complete expected row; its total text
length is checked and consumed with `keep`. Every template string and named
capture map is compared with its complete expected value. Errors propagate to
a failing producer exit. The existing `compare_stdlib.py` driver rejects failed
producers, missing/duplicate cases, changed module/file identities, and changed
operation counts. Its raw JSON documents and summaries are retained alongside
this report, with compiler, runtime, source and wrapper hashes.

The new extraction and replacement cases report ns per complete call
(`operations=1`), at zero, one, 128 and 2,000 matches. Existing matches, find-all
and literal-replace cases remain controls, with their existing operation counts.
The mixed template case expands one 65,536-byte capture followed by 1,999 short
captures. The unused-template control supplies a two-million-byte template and
an input with no matches.

## Results

The strongest runtime result is literal-template replacement: the final medians
fall from 421.77 to 192.65 ns for one match (0.457x), and from 713.51 to
247.67 microseconds for 2,000 matches (0.347x). Before/after ranges are disjoint
across all seven trials for both cases. The initial run independently measured
0.454x and 0.350x, respectively.

The complete [final median table](results/regex-2026-10-29/final/results.md) and
[before/after distributions](results/regex-2026-10-29/final/distributions.md)
include every case, trial-median range and CV. The [environment and input hashes](results/regex-2026-10-29/environment.json)
identify the actual compiler/runtime inputs. The unchanged controls finish at
1.020x / 0.977x / 1.027x (find-all / matches / literal replace).

The final capture-collection median at 2,000 rows is 0.857x, while its initial
median was 0.997x. Dollar-template replacement at 2,000 matches is 0.914x in the
final run and 0.893x initially. Named-group medians also improve, but some case
CVs exceed 20%; these smaller runtime changes are less certain than the literal
win. The reduction in allocation work is independently repeatable.

The mixed long/short case changes from 1.047x initially to 0.972x finally; no
consistent slowdown is established. The unused-large-template control was
1.070x in the final full run, then 1.002x in a [focused seven-pair recheck](results/regex-2026-10-29/unused-focused/results.md)
with five timed samples per process. The empty-template-input case is 1.031x
(about one nanosecond). These tiny cases and the wide trial ranges do not support
a global all-clear or an exact small-speedup claim.

The [initial run](results/regex-2026-10-29/initial/distributions.md) is retained.
Its three preexisting controls swallowed errors or did not verify expected
counts; the final source propagates failures and checks expected results. The
hardened final run is the primary comparison. Both variants always use identical
source within each run; the initial source snapshot is retained separately.
Raw JSONL documents for both campaigns and the focused recheck are committed.

## Allocation diagnostic and rejected alternative

An independent Sol 6.1 review also measured native Rust calls with a forwarding
`System` counting allocator: one warmup and three measured calls, exact complete
output equality/checksums, and output destruction inside the counters. All three
trials had identical counts and returned to zero net live bytes above entry.
These request counts and logical live capacities are not generated musl/StdHeap
RSS, allocator overhead, or transient storage inside `System::realloc`.
The [external allocation probe](regex-allocation-probe.md) records the complete
harness and setup instructions.

| case | allocation calls before / after | requested bytes before / after | peak logical live bytes before / after |
| --- | ---: | ---: | ---: |
| captures, 2,000 rows | 10,002 / 8,003 | 479,680 / 335,728 | 301,968 / 253,968 |
| dollar template, 2,000 matches | 4,001 / 2,001 | 217,719 / 161,528 | 36,928 / 32,816 |
| mixed large/short template | 4,001 / 2,001 | 931,966 / 522,752 | 393,250 / 262,176 |
| literal template, 2,000 matches | 4,001 / 1 | 144,760 / 32,760 | 16,440 / 16,384 |

Zero-match cases were unchanged. The single-row capture case requested fewer
bytes (318 to 294), with a small logical peak increase from 270 to 294 bytes.
Reusing a temporary expansion string instead of eliminating it was rejected:
it raised the mixed-case peak from 393,250 to 524,324 bytes. Direct expansion
removes that capacity retention and the extra copy. Both original and new
dollar-expansion paths build the complete expansion before reporting an exceeded
budget; neither promises a capped-allocation budget.

## Reproduction

Run from the candidate checkout with its benchmark additions. Build the old
runtime separately; both benchmark variants then use the same current compiler
and source. Keep runtime builds sequential because `xtask` publishes one archive
per checkout.

```sh
git worktree add /tmp/ms-regex-before 7e2e62357d5cebc1f144b6ee86f38da247cd2f52
(cd /tmp/ms-regex-before && cargo xtask runtime)
cp /tmp/ms-regex-before/target/ms-native/libms_native.a /tmp/regex-before.a
cargo xtask runtime
cp target/ms-native/libms_native.a /tmp/regex-after.a
cargo build --release --locked -p ms-cli
export REGEX_COMPILER="$(pwd)/target/release/ms"
export REGEX_BEFORE_RUNTIME=/tmp/regex-before.a
export REGEX_AFTER_RUNTIME=/tmp/regex-after.a
export REGEX_BEFORE_CACHE=/tmp/regex-before-cache
export REGEX_AFTER_CACHE=/tmp/regex-after-cache
cat > /tmp/regex-before-ms <<'SH'
#!/bin/sh
exec env MS_BACKEND=cranelift MS_RT_LIB="$REGEX_BEFORE_RUNTIME" MANUSCRIPT_CACHE_DIR="$REGEX_BEFORE_CACHE" "$REGEX_COMPILER" "$@"
SH
cat > /tmp/regex-after-ms <<'SH'
#!/bin/sh
exec env MS_BACKEND=cranelift MS_RT_LIB="$REGEX_AFTER_RUNTIME" MANUSCRIPT_CACHE_DIR="$REGEX_AFTER_CACHE" "$REGEX_COMPILER" "$@"
SH
chmod +x /tmp/regex-before-ms /tmp/regex-after-ms
taskset -c 0 python3 bench/perf/compare_stdlib.py \
  --before /tmp/regex-before-ms --after /tmp/regex-after-ms \
  --filter regex --repeats 7 --samples 3 --output /tmp/regex-comparison
```

## Validation and remaining scope

The called regex fixture covers repeated optional captures, named groups separated
by unnamed groups, participating empty groups, literal/dollar templates, and strict
budgets. Rust regressions additionally cover zero-width adjacency, Unicode
boundaries, full-haystack word-boundary context, unknown template references and
negative limits. Independent review found no blocking correctness issue.

Local checks on the final source:

- `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`,
  and the repository invariant checker passed.
- `cargo nextest run --workspace --no-fail-fast` ran 1,206 tests: 1,203 passed,
  three failed because LLVM debug inspection tools were missing, and one ignored
  test was skipped. After supplying Debian LLVM 19.1.7 `dwarfdump` and `symbolizer`,
  all three failed tests passed in a focused nextest rerun. No test was disabled.
- `cargo test --workspace --doc` passed; the regex crate's Release run passed its
  eight unit tests and recorded regex oracle.
- The called regex fixture passed all six tests in both Release and Debug.
- The final frozen conformance run passed 2,393/2,393 fixtures: 1,603 check,
  531 run, and 259 test fixtures, with no expected or unexpected failures.
- The benchmark project type-checks (19 modules); all 17 measured cases and
  operation counts pass the comparison validator. The standalone allocation
  reproduction was exercised from the documented setup.

The fresh pass covered every pure matching, span, capture, split and replacement
method. Unlimited split streaming trades its exact output reserve for vector
growth and needs separate evidence. First-match captures have no repeated
bookkeeping to reuse; dollar templates still use the upstream `Captures` expansion
API. No new cache, template parser, or engine semantics are introduced.

The timing claim is limited to this host and the explicitly selected Release
backend. Windows, macOS, LLVM runtime comparisons and arbitrary regex workloads
are not established by these measurements.
