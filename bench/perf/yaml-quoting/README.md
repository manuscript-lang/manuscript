# Rejected YAML control-escape experiment

**No production change is retained.** A private fixed-width hex helper made dense
control escapes about 1.37x faster, but a long late-escape control consistently
regressed. Longer interleaved measurements confirm 9.5% slowdown while the identical-binary
A/A medians differ by only 0.3%. The candidate is saved unapplied in
[candidate.patch](candidate.patch), against main
`3cfde58b6216ae4db54aeb3ae4e22ee7d527e323` (zero context; use
`git apply --check --unidiff-zero`). Do not land it based only on target-case gains.

The cause of the off-path regression remains unresolved. Compiler/backend,
ownership/lifetime and parity investigations are outside this campaign's permitted
scope; no such investigation or placement tuning was performed. YAML still has
measured gaps; this is not a clean bill for YAML or all serialization.

## Full controls

Host: Linux-6.18.57-x86_64-with-glibc2.41, AMD EPYC 9V45 96-Core Processor. Official pinned Rust1.99.1,
LLVM23.1.1 Release for Manuscript, and pinned Serde YAML NG0.10.0 dynamic `Value::Mapping`
for Rust. Both inputs are a mapping containing one String. Native runtime archives
are identical between the two Manuscript builds. [Full provenance](results/2026-10-31/full/environment.json)
records source/runtime/binary hashes and commands; [samples](results/2026-10-31/full/samples.jsonl)
retain every timing and [distributions](results/2026-10-31/full/summary.json) include MAD/range.

Twelve position-balanced trials rotate three producers in complete six-trial
blocks. Setup/warm-up/printing are outside timing; complete output equality checks
and release are inside. Every producer's complete output is decoded by Serde YAML
and compared with the input String before measurement; Manuscript before/after
bytes must match exactly. Serde validation is independent of Manuscript, not of
the Rust serializer library. Producers may use different equivalent YAML quoting,
so these are public serialization-plus-validation timings, not identical quote
kernels. Every process validates operation counts and checksums; no other build or
benchmark ran during measurement.

| Input | Before µs | Candidate µs | Rust µs | Before / candidate |
| --- | ---: | ---: | ---: | ---: |
| empty | 0.089 | 0.087 | 0.443 | 1.017x |
| tiny | 0.097 | 0.098 | 0.464 | 0.995x |
| common | 0.146 | 0.146 | 0.774 | 0.995x |
| ascii-16k | 8.835 | 8.878 | 78.643 | 0.995x |
| unicode-16k | 30.010 | 29.354 | 49.951 | 1.022x |
| sparse-escape | 80.745 | 87.922 | 75.524 | 0.918x |
| dense-escape | 304.470 | 221.603 | 79.477 | 1.374x |
| mixed-unicode-escape | 127.012 | 125.296 | 61.673 | 1.014x |

## Longer A/A and candidate controls

The [focused driver](focused.py) runs twelve balanced trials per input, with two
identical baseline labels and one candidate. Each sparse process performs 10,000
operations; dense processes perform 3,000. Raw [records](results/2026-10-31/focused/samples.jsonl),
[binary identities](results/2026-10-31/focused/binaries.json), [driver provenance](results/2026-10-31/focused/provenance.json)
and [distributions](results/2026-10-31/focused/summary.json) retain all 72 observations.

| Input | Baseline A µs | Baseline B µs | Candidate µs |
| --- | ---: | ---: | ---: |
| sparse | 81.084 | 81.298 | 88.933 |
| dense | 306.748 | 306.135 | 220.489 |

The baseline and candidate sparse ranges do not overlap. The A/A ranges overlap;
the target gain therefore does not justify accepting the common-path regression.
Early `initial/` records used a typed Rust map during discovery; final full/focused
records use the dynamic control above. Earlier discovery is not substituted for
matched final evidence.

## Memory and behavior

The [memory driver](memory.py) uses the repository's native [RSS launcher](../representative/rss.c)
to avoid inheriting Python's peak. Five approximately 0.6–1.2MiB shapes, six balanced
trials and all three producers give 90 [RSS records](results/2026-10-31/memory/samples.json).
[Provenance](results/2026-10-31/memory/environment.json) includes driver, launcher,
source and producer hashes. Before/candidate medians are equal for all five
Manuscript shapes; these are whole-process RSS values, not allocation counts.
This does not overturn the timing rejection.

The candidate and restored original both pass five [source regressions](regressions.ms):
plain/Unicode values, named/control escapes, exact C1 output, byte budgets, and
quoted keys with all C0/C1 controls. The restored original also passes all 35
current YAML tests. Repository checks, workspace/control Rust formatting, control
Clippy with warnings denied, Python syntax and diff whitespace pass. Independent
review found no source-level semantic issue: the only hex helper caller passes
0..31 or127..159, so two hex digits after `00` are sufficient.

Full workspace/native/conformance execution is left to required CI because this
campaign excludes backend, ownership/cleanup, Windows and network investigations.
No JSON, parser-algorithm or general Rust-parity claim follows from these tests.

## Reproduction

Use clean base/candidate checkouts. First build original producers, then apply the
saved patch only in the candidate checkout and rebuild; preserve source and binary
hashes. The helper patch changes no public API, but remains rejected on performance.

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
target/release/ms build bench/perf/yaml-quoting/main.ms --build-type Release -o /absolute/path/to/producer
cargo build --release --locked --manifest-path bench/perf/yaml-quoting/rust/Cargo.toml
cc -O2 bench/perf/representative/rss.c -o /absolute/path/to/rss
```

Generate a fresh provenance JSON from the full record's `provenance` object,
updating source/runtime hashes and actual build commands. `run.py` requires the
complete source-key set, nonempty commands, exact base-source hash, candidate source
hash and current harness/lock/tool pins. The saved patch must be applied when
running timings; it is unapplied in this evidence-only tree.

```sh
python3 bench/perf/yaml-quoting/run.py \
  --before /absolute/path/to/before --after /absolute/path/to/candidate \
  --rust /absolute/path/to/yaml-quoting-control --output /fresh/full/output \
  --revision 3cfde58b6216ae4db54aeb3ae4e22ee7d527e323 \
  --toolchain 'rustc1.99.1 LLVM23.1.1 Release serde_yaml_ng0.10.0' \
  --provenance /absolute/path/to/provenance.json
python3 bench/perf/yaml-quoting/focused.py \
  --before /absolute/path/to/before --after /absolute/path/to/candidate \
  --rust /absolute/path/to/yaml-quoting-control --output /fresh/focused/output
python3 bench/perf/yaml-quoting/memory.py \
  --before /absolute/path/to/before --after /absolute/path/to/candidate \
  --rust /absolute/path/to/yaml-quoting-control --rss /absolute/path/to/rss \
  --timing-environment /fresh/full/output/environment.json --output /fresh/memory/output
```

## Newer-main coordination

The evidence-only branch incorporates main
`f33f13359` (including #2057 Unicode blanks). The restored current implementation
passes the five preserved quoting tests and all **36** current YAML tests, including
Unicode spaces. These results preserve that parser fix; the historical timings
remain pinned to 3cfde58b6 and do not establish newer-main performance. Parser
fixes #2083, #2085 and #2097 are independent and pending at this checkpoint. Any
future helper optimization must rebase and repeat key/round-trip/budget/C1 controls
after those changes land. No parsing code or production helper change is in this PR.
