# Local formatter and LSP performance controls

This measures Manuscript's **Rust tooling implementation**, not generated
Manuscript programs against Rust programs. Different language servers and
formatters do not provide equivalent parsing, checking, recovery and output
contracts; no Rust-language parity ratio is claimed here.

The deterministic harness generates valid source from the two `.ms` templates,
checks it, builds the occurrence index, and performs a warm-up before timing.
Completion necessarily includes its own request analysis. Reference, symbol,
semantic-token and completion measurements include JSON construction/rendering;
all result text is consumed in a stable FNV-1a fingerprint. Index queries consume
ordered identity/name/file/offset facts; hover consumes the selected name and
offset. The format control consumes the full formatted source. Each process
checks its aggregate against the repeated warm-up fingerprint; both binaries must agree on the
fingerprint and source byte count. No native compilation is performed.

`compare.py` calibrates repetitions to roughly 30 ms per fresh process, then
alternates AB/BA ordering for nine measured samples. Slow individual queries
can exceed that duration. It rejects failed or mismatched producers and retains
all raw samples. Compare distributions and controls; this is not a CI threshold.

Workloads cover 1/100/1,000/4,000 functions or references, a single early
reference, a 1 MB unrelated trailing comment, Unicode comments, CRLF, and a
100 KB leading comment. Controls cover literal/whitespace/indexed-name hover,
index construction, document symbols, semantic tokens, completion, and formatting.
The fixtures test Unicode within result ranges separately from comment workloads.

`peak_rss_kib` is Linux `/proc/self/status`'s `VmHWM`, read inside the measured
child after the timer stops. It includes source generation, checking and index
setup, so it cannot isolate temporary query allocations. Zero means unavailable;
there are no allocator counts or instruction-count claims.

## Reproduce a comparison

Use the repository's pinned Rust 1.99.1. Build both binaries on the same host
without simultaneous CPU-intensive work. The following also works when the
baseline predates this harness:

```sh
git worktree add --detach .artifacts/lsp-before d4a94aa9283348133542078e22ccaa3b2c9dc348
mkdir -p .artifacts/lsp-before/bench/perf/lsp
cp bench/perf/lsp/Cargo.toml bench/perf/lsp/Cargo.lock \
   bench/perf/lsp/main.rs bench/perf/lsp/function.ms bench/perf/lsp/references.ms \
   .artifacts/lsp-before/bench/perf/lsp/
cargo +1.99.1 build --release --locked \
   --manifest-path .artifacts/lsp-before/bench/perf/lsp/Cargo.toml \
   --target-dir .artifacts/lsp-before-target
cargo +1.99.1 build --release --locked \
   --manifest-path bench/perf/lsp/Cargo.toml --target-dir .artifacts/lsp-after-target
python3 bench/perf/lsp/compare.py \
   .artifacts/lsp-before-target/release/ms-lsp-perf \
   .artifacts/lsp-after-target/release/ms-lsp-perf \
   --out .artifacts/lsp-results.csv --samples 9
```

The standalone Cargo package uses only local frontend/tooling crates and the
same release profile for both binaries (`opt-level=3`, debug info, panic abort;
no LTO or custom CPU flags). Build times and setup are excluded from query times.

To reproduce one workload, use `ms-lsp-perf MODE COUNT ROUNDS SHAPE`; examples
are `references 1000 10 references` and `references-first 1 100 tail`.
The [dated report](results-2026-10-31.md) records revisions, hashes, observations,
rejected candidates and remaining coverage limits.
