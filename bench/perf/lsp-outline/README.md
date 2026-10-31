# Document-outline suffix scans

This measures Manuscript's Rust tooling implementation, not generated programs
against Rust or another language server with different semantics.

The harness generates checked source, builds the occurrence index, then warms
and times complete document-symbol construction, JSON rendering and an FNV-1a
fingerprint. Every process checks its aggregate against repeated warm-up output;
the comparator rejects failed producers, changed identities, fingerprints or
source sizes. All samples are retained. Ten alternating AB/BA samples are balanced
and may be pinned with Linux `taskset` via `--cpu`.

The matrix includes 1/16/128/1,000 declarations with 0/1 KB/100 KB whitespace,
1 MB and CRLF suffixes, large comment suffixes, Unicode/CRLF source, and unchanged
hover/index/semantic/reference/completion/formatter controls. The whitespace
cases render identical symbol JSON across suffix lengths, verified separately
from before/after agreement. Comment suffixes retain their existing range policy.

Setup/checking/builds are excluded except completion's own analysis. Linux
`VmHWM` is read in the child after timing, includes setup, and does not establish
query allocation counts. Zero means unavailable. No native Manuscript program
is built or executed. This is a profiling guide, not a CI timing threshold.

## Reproduce

The baseline is `ffcbe7b6bb9ed7c7c466797b5aff7a8ff441f60a`, with identical
Rust 1.99.1 release settings and harness source on both trees:

```sh
git worktree add --detach .artifacts/outline-before ffcbe7b6bb9ed7c7c466797b5aff7a8ff441f60a
mkdir -p .artifacts/outline-before/bench/perf/lsp-outline
cp bench/perf/lsp-outline/Cargo.toml bench/perf/lsp-outline/Cargo.lock \
   bench/perf/lsp-outline/main.rs bench/perf/lsp-outline/function.ms \
   bench/perf/lsp-outline/references.ms .artifacts/outline-before/bench/perf/lsp-outline/
cargo +1.99.1 build --release --locked \
   --manifest-path .artifacts/outline-before/bench/perf/lsp-outline/Cargo.toml \
   --target-dir .artifacts/outline-before-target
cargo +1.99.1 build --release --locked \
   --manifest-path bench/perf/lsp-outline/Cargo.toml --target-dir .artifacts/outline-after-target
python3 bench/perf/lsp-outline/compare.py \
   .artifacts/outline-before-target/release/ms-lsp-outline-perf \
   .artifacts/outline-after-target/release/ms-lsp-outline-perf \
   --out .artifacts/outline-results.csv --samples 10 --cpu 0
```

Use an allowed CPU, or omit `--cpu` and record that difference. No simultaneous
build/test jobs should run during measurement. Release uses `opt-level=3`, debug
info, panic abort, no LTO/custom CPU flags, and only local frontend/tooling crates.
One case is `ms-lsp-outline-perf symbols 1000 10 spaces-100000`.

See [the dated report](results-2026-10-31.md) for raw samples, all controls,
artifact hashes, source qualifications and remaining integration checks.
