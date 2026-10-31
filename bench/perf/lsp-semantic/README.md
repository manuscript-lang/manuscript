# Ordered semantic-token positions

This benchmarks Manuscript's Rust language-server implementation. It does not
compare generated Manuscript programs with Rust programs, or claim equivalence
with another language server's parsing, recovery or highlighting contracts.

The standalone harness generates deterministic source from `.ms`/`.src` fixtures,
checks valid input, builds its occurrence index and warms each query before
timing. Incomplete inputs must fail checking and strict lexing; their semantic
queries exercise the forgiving scanner. Completion includes its own request
analysis. Semantic, symbol, reference and completion results include JSON
rendering and consume the complete rendered output in an FNV-1a fingerprint.
Hover fingerprints consume selected offset/text; index fingerprints consume
ordered identities/names/files/ranges; formatting consumes the full output.

Each process checks its aggregate against the repeated warm-up fingerprint.
The comparator rejects producer failures, wrong identities, mismatched
fingerprints or changed source sizes. All samples are retained. Ten samples
alternate AB/BA with equal first/second counts; repetitions target about 30 ms
per process. This is a profiling guide, not a CI timing gate.

The final matrix contains 68 workloads: lists of 1–8,192 items on one/many lines;
Unicode strings; LF/CRLF; ordinary 1/100/1,000-function sources; incomplete
snapshots; long leading/trailing comments; plus unchanged hover, index, symbol,
reference, completion and formatter controls. Setup and compilation are excluded
from query timers except completion's internal analysis. No native Manuscript
program is compiled or executed.

Linux `VmHWM` is read inside each child after timing. It includes setup/checking,
so it cannot isolate query allocations; zero means unavailable. No allocator or
instruction-count claim is made. The helper removes a line-index vector from
the semantic path, but memory differences must not be inferred from wall time.

## Reproduce

Use pinned Rust 1.99.1 and the same harness for both trees. The recorded baseline
is `f33f13359a02b59467f042eb67d6ecd06d706c7a`. It predates this harness:

```sh
git worktree add --detach .artifacts/semantic-before f33f13359a02b59467f042eb67d6ecd06d706c7a
mkdir -p .artifacts/semantic-before/bench/perf/lsp-semantic
cp bench/perf/lsp-semantic/Cargo.toml bench/perf/lsp-semantic/Cargo.lock \
   bench/perf/lsp-semantic/main.rs bench/perf/lsp-semantic/function.ms \
   bench/perf/lsp-semantic/references.ms bench/perf/lsp-semantic/list.ms \
   bench/perf/lsp-semantic/unfinished.src .artifacts/semantic-before/bench/perf/lsp-semantic/
cargo +1.99.1 build --release --locked \
   --manifest-path .artifacts/semantic-before/bench/perf/lsp-semantic/Cargo.toml \
   --target-dir .artifacts/semantic-before-target
cargo +1.99.1 build --release --locked \
   --manifest-path bench/perf/lsp-semantic/Cargo.toml --target-dir .artifacts/semantic-after-target
python3 bench/perf/lsp-semantic/compare.py \
   .artifacts/semantic-before-target/release/ms-lsp-semantic-perf \
   .artifacts/semantic-after-target/release/ms-lsp-semantic-perf \
   --out .artifacts/semantic-results.csv --samples 10 --cpu 0
```

Use an allowed CPU for `--cpu` (Linux `taskset`); omit it if unavailable and
record that difference. Do not run simultaneous builds/tests during timing.
Both packages use release `opt-level=3`, debug info, panic abort, no LTO and no
custom CPU flags. All dependencies are the local frontend/tooling crates.
One case is `ms-lsp-semantic-perf semantic 8192 10 list-flat`.

See [the dated report](results-2026-10-31.md) for all medians, raw samples,
artifact hashes, measured tiny-case costs and coverage limits.
