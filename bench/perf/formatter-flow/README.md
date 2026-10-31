# Formatter flow and suffix controls

This compares two versions of Manuscript's Rust formatter implementation. It is
not a generated Manuscript-versus-Rust program comparison: other formatters do
not provide the same syntax, recovery and canonical-output contract.

The standalone harness generates source from `.ms` templates before timing.
It formats the original source once and that output once to verify idempotence
(two untimed formatting calls), then measures the complete format
operation (lexing, parsing, layout and a full-output FNV-1a fingerprint). Both
binaries must agree on fingerprints and source/output byte counts. The fixed
logical source path is the same for both producers. No native compilation occurs.

`compare.py` calibrates each producer to approximately 30 ms per measured child,
then uses ten balanced AB/BA fresh-process samples for every workload. One slow
query can exceed that duration. All samples are retained; failures and output
mismatches stop the run. `--cpu 0` pins each child on Linux with `taskset`.

The 59 cases include implicit flow steps, explicit pipes and ordinary members;
1/8/28/29/30/31/32/128/512/2,048 steps; cutoff boundary neighbors; nonempty call
groups, clause colons, comments, Unicode text and CRLF; 1/100/1,000 ordinary
functions; and 1/32/512/8,192 flat/multiline list items. Syntax acceptance and
format idempotence are checked for every measured child. These formatter inputs
are not type-checked native programs, and no application-throughput claim follows.

`peak_rss_kib` is the measured child's Linux `VmHWM`, read after timing. It
includes source setup, warm-up, idempotence and formatting; it does not isolate
query allocations. Zero means unavailable. No allocator/instruction counters
were available.

## Reproduce

Use pinned Rust/Cargo 1.99.1, identical release profiles, one host, and no
simultaneous builds/tests while measuring. The baseline may predate the harness:

```sh
git worktree add --detach .artifacts/flow-before 26d586480a0aa786035d3def7bfe47651c96e297
mkdir -p .artifacts/flow-before/bench/perf
cp -R bench/perf/formatter-flow .artifacts/flow-before/bench/perf/
cargo +1.99.1 build --release --locked \
  --manifest-path .artifacts/flow-before/bench/perf/formatter-flow/Cargo.toml \
  --target-dir .artifacts/flow-before-target
cargo +1.99.1 build --release --locked \
  --manifest-path bench/perf/formatter-flow/Cargo.toml \
  --target-dir .artifacts/flow-after-target
python3 bench/perf/formatter-flow/compare.py \
  .artifacts/flow-before-target/release/ms-formatter-flow-perf \
  .artifacts/flow-after-target/release/ms-formatter-flow-perf \
  --out .artifacts/flow-results.csv --samples 10 --cpu 0
```

Both packages use default release `opt-level=3`, debug info and panic abort,
without LTO or custom CPU flags. Build/setup times are excluded. For one case,
run `ms-formatter-flow-perf COUNT ROUNDS SHAPE`, for example `512 5 flow`.
The dated report records the immutable baseline, hashes, full matrix and limits.
