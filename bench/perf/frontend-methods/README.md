# Method candidate indexes — 2026-10-28

Refs #1812. Reduce repeated method lookup and implementation overlap scans with
candidate buckets keyed by nominal receiver identity (and operation name for
lookup). Generic argument unification, bounds, visibility and declaration order
remain checked at use. Registration includes synthesized methods, standard cache
adoption, and editor queries. This does not claim that the whole quadratic
frontend defect is fixed.

Baseline: `9df238693f97777dad6ed727dfa815ac0ac65d9f`. Candidate: the method index
change recorded in this directory's `source-hashes.json`; the three production
source fingerprints identify the measured implementation independently of
subsequent documentation or rebasing. Same machine and workloads for both builds.

| Workload | Types | Baseline median ms | Candidate median ms | Speedup |
| --- | ---: | ---: | ---: | ---: |
| same | 512 | 19.687 | 7.166 | 2.75x |
| same | 1024 | 69.007 | 17.460 | 3.95x |
| same | 2048 | 283.158 | 49.769 | 5.69x |
| unique | 512 | 13.328 | 7.455 | 1.79x |
| unique | 1024 | 45.887 | 17.895 | 2.56x |
| unique | 2048 | 175.058 | 49.179 | 3.56x |
| nocall | 512 | 9.753 | 5.993 | 1.63x |
| nocall | 1024 | 30.602 | 14.265 | 2.15x |
| nocall | 2048 | 90.460 | 39.847 | 2.27x |
| field | 512 | 2.604 | 2.433 | 1.07x |
| field | 1024 | 5.219 | 5.344 | 0.98x |
| field | 2048 | 11.925 | 12.123 | 0.98x |

Same-name doubling ratios improve from 3.51/4.10 to 2.44/2.85. Residual
superlinear total frontend growth remains unattributed. No profiling or
performance-counter investigation was performed. The direct-field control
remains approximately unchanged; these are frontend measurements, not native
execution or whole-CLI measurements.

Linux x86_64, kernel 6.18.55, glibc 2.41, AMD EPYC 9V74 VM, Rust 1.99.1.
Release opt-level 3, debug 1, panic abort. Each process pinned to CPU 0. Five fresh
processes per workload, shuffled seed 1729, one first check and five warm checks
per process (25 warm samples/row). Baseline suite ran before candidate suite;
there were no overlapping benchmark/build jobs, but host isolation is not
claimed. Raw JSON retains every first/warm timing and standard startup time;
`environment.json` records machine details. Parsing, loading, input generation,
validation and destruction are outside the check timer. Every sample checks
zero diagnostics, no unused locals and an Int main result. The harness directly
calls Checker::check_modules and bypasses ownership analysis. No native output
was built or executed.

Nine frontend-only unit tests verify constant-size buckets at 128/256/512 unrelated
methods, generic receiver and operation parameters, declared and interface bounds,
specialization overlap, ambiguity ordering, duplicate inherent operations, invalid
receivers, local extension visibility, defining-module methods and editor queries.
Eight fixture groups have exact before/after diagnostic parity, including file,
position, phase, message, fix and report order (`diagnostic-parity.json`).

Normal workspace test resolution stopped before compilation because the offline
registry lacks cranelift-frontend. The source-only adapter compiles the original
checker modules and runs the new unit tests without the public ownership wrapper.
Full workspace clippy, nextest, conformance and native/codegen checks were not run
within this frontend-only scope.

## Reproduce

From this directory, set REPO to a checkout of the desired revision and OUT to a
new directory outside that checkout. With Cargo/Rust 1.99.1 available:

```sh
python3 setup.py "$REPO" "$OUT/harness"
cd "$OUT"
python3 "$REPO/bench/perf/frontend-methods/generate.py"
cargo build --release --offline --manifest-path harness/Cargo.toml
python3 "$REPO/bench/perf/frontend-methods/measure.py" \
  harness/target/release/type-bench methods/same-{512,1024,2048}.ms \
  methods/unique-{512,1024,2048}.ms methods/nocall-{512,1024,2048}.ms \
  methods/field-{512,1024,2048}.ms
```

Repeat for baseline and candidate in separate output directories. The baseline
checkout predates these scripts, so use the candidate's script paths for both.
Run only the focused tests in the candidate adapter:

```sh
cargo test --offline --manifest-path "$OUT/harness/Cargo.toml" \
  --lib method_candidates_tests
```
