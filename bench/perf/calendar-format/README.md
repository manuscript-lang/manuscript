# Calendar formatting without temporary heap strings

`Timestamp.format` previously formatted every numeric token into its own String
and cloned the zone abbreviation before scanning a pattern. Empty, literal and
single-token patterns paid for unused tokens. The replacement formats encountered
numeric tokens into eight fixed 32-byte buffers, once per token per call. It
appends the existing zone label directly. The first-token-wins byte scan, padding,
millisecond truncation, zone validation and growing final output are preserved.

The cache uses 320 bytes of bounded numeric storage including length metadata.
Every signed i64 field needs at most 20 characters; the offset also fits. The
ordinary Rust formatter retains minimum widths, including local years `0` and
`10000` near the supported UTC limits. Buffer write failures are checked.
The removal of numeric scratch heap allocations and the extra zone clone follows
from source; no allocator, RSS or instruction-count measurement is claimed.

## Release comparison, 2026-10-31

Baseline: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. Only
`crates/ms-std-time/src/core_time.rs` changes production behavior. Before and after
use the same compiler and workload, with separately supplied native archives.

Host: Linux x86-64 6.18.57, AMD EPYC 9V74, five visible CPUs, four-CPU cgroup
quota, 16 GiB cgroup memory limit. The launcher and children were pinned to CPU 0;
no local build or test ran during measurement. This is a shared VM, without
flushing OS caches. Rust is `1.99.1 (58cf8f9c3 2026-10-13)` and Cargo is
`1.99.1 (5f94df478 2026-08-27)`. Native libraries use the repository's musl release
profile. Manuscript uses Release with `MS_BACKEND=llvm` and the repository-pinned
LLVM 23.1.1 directory explicitly supplied through `MS_LLVM_TOOLS`.

The Rust control uses the same calendar conversion, ordered byte scan, memoized
tokens, inputs and byte outputs. It uses an ordinary lazy String cache rather
than bounded numeric buffers. The workload enables overflow checks; dependencies
retain the native release profile. It is a focused hand-written control, not an
independent calendar implementation or a comparison against every Rust library.
Rust links the host libc; Manuscript links musl. The control is built against the
candidate crate, but calls only the unchanged calendar conversion.

Two timestamps are constructed before timing. Every iteration formats one,
checks its **entire output inside the timed region**, and consumes its length.
Python independently supplies the exact expected strings. Setup, argument
parsing, final printing and process startup are outside the inner timer. Results
therefore measure formatting plus validation. Child CPU measurements in the raw
file cover the whole producer process and are distinct from the inner timer.

The final session has one warmup and 12 balanced paired repeats per case, rotating
case order, plus an interleaved identical-baseline A/A label. All **520 producer
invocations** passed output/count/checksum validation. Counts are 200,000 for
short patterns and scaled equally across producers for long patterns.

Values below are median inner **ns/operation**. Paired ratios are medians of
per-trial ratios, rather than ratios of the displayed medians.

| Pattern | Before | After | Rust | After/before paired | A/A paired |
| --- | ---: | ---: | ---: | ---: | ---: |
| Empty | 341.86 | 81.08 | 109.80 | 0.240 | 1.017 |
| Literal | 575.93 | 132.00 | 92.87 | 0.228 | 1.000 |
| Year | 364.98 | 117.79 | 97.17 | 0.322 | 0.996 |
| Date | 413.06 | 173.84 | 165.71 | 0.401 | 0.986 |
| Datetime | 552.06 | 263.61 | 280.81 | 0.469 | 0.996 |
| All tokens | 683.60 | 346.72 | 394.56 | 0.520 | 0.995 |
| Repeated tokens | 2767.27 | 1113.33 | 1145.83 | 0.407 | 1.027 |
| Long literal | 87037.62 | 12029.63 | 10295.17 | 0.137 | 0.992 |
| Partial prefixes | 770.62 | 161.88 | 112.53 | 0.211 | 0.996 |
| Unicode | 990.93 | 344.11 | 326.20 | 0.343 | 0.974 |

The candidate was faster in all 12 pairs of every case. The A/A paired medians
range from 0.974 to 1.027; individual min/max observations and all raw samples are
retained in [the final data](results/2026-10-31.jsonl). The candidate retains Rust
gaps for literal text, year-only and partial-prefix patterns; no universal parity
or all-platform performance claim follows. Named/fixed zones and extreme years
have correctness coverage, but these timed workloads use UTC only.

Initial exploratory sessions used a character-scanning Rust control. Their raw
data remains in local `.artifacts/calendar-format/{baseline,candidate}.jsonl`;
those Rust ratios are superseded by the matched byte-scanning final session.

## Correctness and review

- `format_matches_eager_renderer_across_patterns_and_zones`: 24,576 exact
  comparisons against the prior eager renderer across 512 timestamps, eight
  patterns and six zones, including invalid UTF-8 bytes.
- `format_preserves_extended_years_and_output_growth`: explicit year 0/10000,
  fractional truncation, both offset signs and repeated expanding tokens.
- `format_validates_zone_even_without_tokens`: invalid zones still fail for
  empty/literal patterns.
- `calendar-format-tokens.ms`: public calls exercise adjacent/partial tokens,
  Unicode, empty/literal text, errors and extended years in Debug and Release.
- All 10 `ms-std-time` tests, both new source tests and seven existing time source
  tests pass. The selected `stdlib-time` conformance pass is 18/18. Workspace
  clippy, formatting and repository invariants pass. Full workspace tests and
  unrelated conformance paths were not run in this scoped lane.
- Independent Sol 6.1 read-only review found no correctness blocker and checked
  the fixed capacity, token memoization and benchmark equivalence. It did not run
  the measurements.

## Reproduce

Build the baseline native archive at the pinned baseline in an isolated worktree,
then build the candidate archive and compiler using the repository guidance.
Use the same compiler for both programs, and the same final `main.ms` for both:

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
cargo build --release --manifest-path bench/perf/calendar-format/rust/Cargo.toml
MS_BACKEND=llvm MS_LLVM_TOOLS="$LLVM_TOOLS" MS_RT_LIB="$BEFORE_ARCHIVE" \
  target/release/ms build bench/perf/calendar-format/main.ms --build-type Release -o /tmp/calendar-before
MS_BACKEND=llvm MS_LLVM_TOOLS="$LLVM_TOOLS" MS_RT_LIB="$PWD/target/ms-native/libms_native.a" \
  target/release/ms build bench/perf/calendar-format/main.ms --build-type Release -o /tmp/calendar-after
MS_BACKEND=llvm MS_LLVM_TOOLS="$LLVM_TOOLS" python3 bench/perf/calendar-format/repeat.py \
  --producer before=/tmp/calendar-before --producer after=/tmp/calendar-after \
  --producer rust="$PWD/bench/perf/calendar-format/rust/target/release/calendar-format-control::rust" \
  --producer before-AA=/tmp/calendar-before --repeats 12
```

The raw file records workload/control/source hashes and executable hashes. Its
current-source hashes describe the candidate, not the older baseline archive.
The baseline archive was built from the pinned clean revision before any edit;
the candidate archive was built after the production patch. Binaries and native
archives are local evidence and are not published in this repository.

```text
compiler e0f8d0152bf68b04e9f0a6fc2ca876d4c51328d2e58b94dcac322b2c5b71daeb
baseline archive 4ef63cd2ca0418a2b7b4d9590d001af06bd51413af8b1861228da795f80356be
candidate archive c15936c3b6cfdbd2e86860670542b293dccef78ec11829c57a5c546fed4d87c8
before executable ef09de83d69ce7dfbeec1734e27563d6dd776e28f3469dc619db34579858e191
after executable a248bb23fb240fc2897181a108fe4b157f0c25dc0268c8568247a9f5fdf28289
Rust executable e1e4b99e0af98f56aeadb5299574cc6767685cad75a4ea6b16d1227575059503
```
