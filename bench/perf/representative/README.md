# Representative compiler and program measurements

This is a diagnostic harness, not a CI performance threshold. It covers the unchanged
inventory/order, CSV aggregation and log-analyzer reference programs from `bench/agent`,
using their independent Python output oracles. It does not measure agent performance.
The generated scalar-rule programs isolate compiler scaling; they are not application
runtime benchmarks. `hello` exposes fixed startup/build cost.

`prepare.py` creates deterministic inputs, expected outputs, source copies, ordinary
correctness cases and SHA-256 manifests. `run.py` rejects failed builds and incorrect
full outputs. Trials alternate program and compiler order. Trial `-1` is a discarded
warm-up. Build validation executes separately from the timed compilation.

Build both compiler revisions with the same pinned Rust toolchain and the pinned
LLVM bundle from `scripts/lld.lock`. Save the binaries under different names. Build
the stage driver separately with `cargo build --release --locked -p ms-build --example
perf_stages`. It uses the same public passes as Release and requires a real LLVM
object; it cannot silently measure a Cranelift fallback.

For the recorded campaign the base is `414d66451b1efe8acde9cd31097dcb456ee62b0b`
and the production change is `f24a068e88a827e4ae10956b84b3c546a0cc819e`.
Use separate worktrees for those revisions and copy this diagnostic example into
the baseline worktree before building it; the example itself does not change the
compiler. Run `sh scripts/fetch-lld.sh` and `cargo xtask runtime` before the compiler
build, as required by those revisions. Record setup downloads separately. Keep the
same runtime archive and tool bundle for both stage binaries.
The measured local optimization commit can be reconstructed on the baseline by
running `git apply --unidiff-zero` on `evidence-2026-10-24/optimization.patch`;
subsequent rebases must not be
presented as the revision that produced these historical measurements.

```sh
python3 bench/perf/representative/prepare.py .artifacts/representative/inputs
python3 bench/perf/representative/run.py \
  --inputs .artifacts/representative/inputs --output .artifacts/representative/comparison \
  --ms before=/absolute/path/ms-before --ms after=/absolute/path/ms-after \
  --phase build --repeats 7
python3 bench/perf/representative/run.py \
  --inputs .artifacts/representative/inputs --output .artifacts/representative/comparison \
  --ms before=/absolute/path/ms-before --ms after=/absolute/path/ms-after \
  --phase runtime --repeats 9
```

Additional phases:

- `tooling`: actual CLI `check --json`, `inspect`, and `diagram`, with stable-output checks.
- `cold`: a unique empty `XDG_CACHE_HOME` on every trial. This measures bundled-tool
  and runtime extraction, **not** cold OS page caches; it performs no build-time download.
- `stages`: `--stages before=/absolute/path/perf_stages-before` (and `after=...`). The
  driver separates load/parse, checking, lowering, checked-program destruction, verification,
  LLVM availability, MIR optimization, code generation, object writes, linking and MIR
  destruction. Python wrappers record actual `opt` and `llc` invocations and their resources.
  Their interpreter startup adds overhead: use the unwrapped `build` phase for end-to-end
  claims, and tool child times for stage diagnosis. `MS_PERF_MIR_PASSES=1` enables a diagnostic
  replay of the MIR pipeline, which must be kept in sync with `ms-mir/src/opt/mod.rs`.
- `memory` and `memory-build`: separate RSS trials using `--rss /absolute/path/rss`.
  Build that helper with `gcc -O2 -Wall -Wextra -Werror bench/perf/representative/rss.c -o rss`.
  Its native fork isolates the child from Python's inherited high-water mark. Linux
  `ru_maxrss` is the maximum RSS of one process in the waited tree, **not** simultaneous
  aggregate tree memory, virtual address reservations or allocator live bytes. The raw
  timing phases retain their launcher-tree RSS for transparency; use isolated trials
  for reported memory, especially small executables.

Use `--cases` for a comma-separated subset or to add `rules-1000,rules-2000,rules-4000`.
The normal runtime/build phases use the embedded backend, with override variables cleared.
Record actual child execution independently (e.g. `strace -f -e execve` on Linux). On the
baseline revision the build JSON hardcodes `cranelift`, so that field is not evidence of
which backend ran. The stage wrapper verifies the ordered pair `opt`, `llc` on every run.

Keep compiler/tool hashes, the base SHA and exact patch, raw JSONL, input hashes and correctness
results together. Do not run builds or other CPU work alongside a timed suite. Each trial
starts a fresh process with warm filesystem pages; compiler in-process caches are cold.
Only the `cold` phase clears extraction caches. Reusing an output directory appends records;
stage metric paths deliberately reject accidental duplicate trials. Use a new output
directory for a fresh campaign.

To reproduce the checked Rust context, compile the `main.rs` copies produced by
`prepare.py` into the same output directory as the measured Manuscript executables:

```sh
for case in c03-csv-group-sum c13-inventory-orders c25-log-analyzer; do
  rustc --edition 2021 --target x86_64-unknown-linux-musl \
    -C opt-level=3 -C overflow-checks=on -C force-frame-pointers=yes \
    -C panic=abort -C codegen-units=1 \
    ".artifacts/representative/inputs/$case/main.rs" \
    -o ".artifacts/representative/comparison/rust-$case"
done
```

Use the `runtime` phase with `--ms before=/absolute/path/ms-before --ms rust=/unused`
and those three `--cases` to interleave existing executables (that phase does not
invoke the compiler paths). Run the `memory` phase separately with `--rss`.
`check_outputs.py --inputs INPUTS --output OUTPUT --before MS_BEFORE --after MS_AFTER`
checks optimized MIR equality, existing before/after native executable equality and
ordinary reference cases for all existing labels, including `rust`.
`python3 bench/perf/representative/summarize.py OUTPUT` produces the medians and
ranges from successful measured trials. Retain the original JSONL alongside it.

The checked-in report keeps compact samples and hashes only. Generated inputs,
binaries, full logs and new raw campaigns belong under ignored `.artifacts/`.
