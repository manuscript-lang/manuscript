# TOML control-escape performance

On 2026-10-31, replacing general radix conversion and zero-padding in the private
TOML `hex4` helper made the dense-control workload **1.46x faster**. Its only caller
passes ASCII controls (`0..31` or `127`), so `00` and two hexadecimal digits preserve
exact output. The original traversal and append calls remain intact.

The other seven controls change by at most 2.2% in this run; their ranges overlap.
The retained patch does not establish general parity with Rust: long ordinary
strings and mixed Unicode/escapes still have substantial gaps.

## Matched final controls

Base: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. Candidate source SHA-256 and every
binary/source/runtime digest are in [environment.json](results/2026-10-31/environment.json).
Host: Linux x86-64, AMD EPYC 9V45 96-Core Processor. Both builds use Rust
1.99.1; Manuscript uses its pinned LLVM 23.1.1 Release pipeline and musl runtime.
The idiomatic Rust control uses pinned `toml` 0.9.8, `Value::Table` and `to_string`,
with opt-level 3 and its lockfile committed. No compiler/runtime/native changes
are part of this patch.

These are **public table serialization plus a full-output equality guard** timings,
not isolated identical quoting algorithms. Both inputs are one-string tables.
Rust may choose different equivalent TOML quoting; output lengths are recorded
independently. Python `tomllib` validates each producer's complete output against
the source value, and Manuscript before/after output must be byte-identical.
Every timed iteration checks its complete output and contributes its byte length
to a validated checksum. Input loading, table construction, initial warm-up and
printing are outside timing; result release and equality validation are included.

Twelve interleaved process trials use complete six-trial ordering blocks, equal
operation counts, and baseline calibration to at least 50ms per process. No other
build or benchmark ran during timing. Raw [samples](results/2026-10-31/samples.jsonl)
and [distributions](results/2026-10-31/summary.json) retain median, MAD, min and max.
No wall-clock CI threshold is added.

| Input | Before µs | After µs | Rust µs | Before / after | After / Rust |
| --- | ---: | ---: | ---: | ---: | ---: |
| empty | 0.112 | 0.112 | 0.116 | 0.993x | 0.971x |
| tiny | 0.131 | 0.134 | 0.128 | 0.979x | 1.046x |
| common | 0.527 | 0.524 | 0.220 | 1.007x | 2.379x |
| ascii-16k | 82.170 | 82.758 | 18.710 | 0.993x | 4.423x |
| unicode-16k | 115.344 | 115.148 | 17.532 | 1.002x | 6.568x |
| sparse-escape | 81.626 | 82.796 | 19.150 | 0.986x | 4.324x |
| dense-escape | 180.731 | 123.954 | 135.868 | 1.458x | 0.912x |
| mixed-unicode-escape | 125.284 | 124.854 | 11.501 | 1.003x | 10.856x |

## Memory controls

The existing native [RSS launcher](../representative/rss.c) starts after Python's
own exec high-water mark, avoiding inherited Python RSS. Six balanced trials use
approximately 0.6–1.2MiB strings and one timed call after setup. These are whole
process peak RSS measurements, not allocation counts; small differences include
binary/process overhead. The retained helper has no new large buffer and no
material increase in these controls. Raw [memory records](results/2026-10-31/memory.json)
include input/output sizes and every sample; [memory provenance](results/2026-10-31/memory-environment.json)
records producer/launcher/source hashes. The committed `memory.py` generates all
five inputs, checks full outputs, verifies the timing binaries and runs the launcher.

| Input | Before KiB | After KiB | Rust KiB |
| --- | ---: | ---: | ---: |
| ascii | 4972 | 4944 | 5170 |
| unicode | 5740 | 5712 | 5946 |
| sparse | 4972 | 4944 | 5184 |
| dense | 8300 | 8272 | 7404 |
| mixed | 5612 | 5584 | 5432 |

## Rejected alternatives

[Historical records](results/2026-10-31/rejected/) retain all measured candidates:

- `clean-scan`: scan bytes, then use the old character fallback. A late escape
  caused a second traversal and about 25% slowdown.
- `batched-hex4`: copy plain UTF-8 runs between escapes. Common text improved,
  but dense controls regressed about 8%.
- `eager-builder`: direct ASCII hex emission fixed dense controls, while eagerly
  creating the builder regressed tiny/empty values by about 10%.
- `eager-bytes`: defer the builder, keeping an eager byte copy. Timing improved,
  but large plain Unicode peak RSS rose from 5740 to 6864KiB.
- `deferred-char-scan`: defer bytes until an escape, using a character scan. Memory
  improved, but large ordinary-text gains shrank to around 10%. Its source digest
  is retained; a complete source snapshot was not captured for this intermediate.
- `batched-memory`: scan scalar values before batching. All timing controls improved,
  including 6.9x on ASCII, but a large string with one late escape used 8140KiB
  instead of 4972KiB peak RSS (64% more). This version is rejected.
- `direct-control`: retain original traversal but emit three fragments directly.
  Dense controls improved 2.29x while ordinary ASCII/late-escape controls regressed
  5–6%, beyond their MAD. Preserve the original append interface instead.

The first two historical runs used nine trials before independent review corrected
position balance. The first also observed only output length. They are exploratory
records, not final evidence. Later records use full-content guards and twelve
balanced trials. Patches and source/binary digests are retained where captured;
none of the rejected variants is applied. Historical patches use zero context
(`git apply --unidiff-zero` against the pinned base) to keep patch artifacts free
of whitespace-only context records.

## Checks and limits

Passed: four new quoting tests (plain/Unicode values, escaped values, exact output
budgets, quoted keys and every ASCII control), all fourteen current TOML source
tests, all twelve corpus TOML tests, repository invariants, workspace Rust formatting,
control formatting/Clippy with warnings denied, Python syntax, and diff whitespace.
Independent review found no correctness blocker in the final helper or its caller.
No GitHub approval was submitted on the user's behalf.

Full workspace/native/conformance execution is left to normal required CI because
this campaign excludes backend, ownership/cleanup, Windows and network investigations.
Final combined-main replay is required after merge. This is a focused TOML quoting
result: JSON, YAML, other parser algorithms and denied scopes are not clean claims.

## Reproduction

Use separate clean checkouts for the pinned base and candidate. Copy this unchanged
`main.ms` into the baseline checkout. Build the compiler in each with the repository's
pinned toolchain and official cached native tools, then build both producers:

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
target/release/ms build bench/perf/toml-quoting/main.ms --build-type Release -o /absolute/path/to/producer
cargo build --release --locked --manifest-path bench/perf/toml-quoting/rust/Cargo.toml
cc -O2 bench/perf/representative/rss.c -o /absolute/path/to/rss
```

Use a writable `XDG_CACHE_HOME` if the default home cache is read-only. Build setup
is outside measurement. Copy the final record's `provenance` object into a new JSON
file, update its hashes from these fresh builds and record the actual commands.
`run.py` requires the exact source/runtime key set, nonempty build commands, the
base source hash, current candidate source hash and current harness/lock/tool pins
to match; it rejects stale or incomplete provenance before timing.

```sh
python3 bench/perf/toml-quoting/run.py \
  --before /absolute/path/to/before \
  --after /absolute/path/to/after \
  --rust /absolute/path/to/toml-quoting-control \
  --output /fresh/output/directory \
  --revision d4a94aa9283348133542078e22ccaa3b2c9dc348 \
  --toolchain 'rustc 1.99.1; LLVM 23.1.1; Release' \
  --provenance /absolute/path/to/provenance.json
```

The runner fails on producer errors, malformed/missing timing fields, wrong operation
counts/checksums, semantic mismatch, changed Manuscript output, or incomplete
samples. It writes the final summary only after every case and trial validates.

Replay the separate RSS controls after the timing run:

```sh
python3 bench/perf/toml-quoting/memory.py \
  --before /absolute/path/to/before \
  --after /absolute/path/to/after \
  --rust /absolute/path/to/toml-quoting-control \
  --rss /absolute/path/to/rss \
  --timing-environment /fresh/timing/output/environment.json \
  --output /fresh/memory/output
```
