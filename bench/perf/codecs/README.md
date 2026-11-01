# Typed JSON Base64 decoding

This focused runtime benchmark decodes `List[Bytes]` through typed JSON parsing. Each
list has a configurable number of identical Base64 strings. Empty and small blobs
expose per-value setup; larger blobs check scaling. The public
`@std/data/encoding.ms` Base64 functions have source implementations; this benchmark
measures the native decoder used by typed JSON, not that source decoder.

The program builds inputs before starting its timer. Each timed iteration parses,
checks the list length, compares every decoded byte sequence against the original,
and consumes the decoded lengths in a printed checksum. Thus timings include
result validation and destruction, but exclude compilation, input generation,
process launch and reporting. Producer failures and unexpected output fail the
comparison. There is no performance CI threshold.

Build the baseline runtime at `4c0a1cb820e772f56a0c831a0f2fe37fbc96a9a7` and the
changed runtime with the same pinned Rust toolchain and `cargo xtask runtime`.
The exact source delta is retained as `evidence-2026-10-29/fix.patch`; apply it to
the baseline with `git apply --unidiff-zero` to reconstruct the changed runtime.
Save each `target/ms-native/libms_native.a` as an absolute path. Build one compiler
with `cargo build --release --locked -p ms-cli`; only the linked native archive
changes between the generated programs:

```sh
MS_RT_LIB=/absolute/path/runtime-before.a target/release/ms build \
  bench/perf/codecs/ms.toml --build-type Release -o /tmp/codecs-before
MS_RT_LIB=/absolute/path/runtime-after.a target/release/ms build \
  bench/perf/codecs/ms.toml --build-type Release -o /tmp/codecs-after
python3 bench/perf/codecs/compare.py /tmp/codecs-before /tmp/codecs-after \
  /tmp/codecs-results --pairs 9
```

Use the same writable `XDG_CACHE_HOME` and pinned `MS_LLVM_TOOLS` for both builds.
Clear backend/vectorization overrides, record actual `opt` and `llc` invocations,
and reject an unexpected Cranelift fallback. Run after all compilation and other
CPU work finishes. The comparison alternates before/after process order, discards
one warm-up pair per case, retains every sample, and records executable hashes.
Each label must produce exactly one complete row with the requested case identity
and the expected checksum. The elapsed clock surrounds only the decode loop.
Results are comparable only on the same machine and settings.

[The 2026-10-29 report](results-2026-10-29.md) retains the paired distributions,
identities, disassembly, and bounded follow-up findings.

The [JSON syntax-error benchmark](json-failure/README.md) covers the independent
second-pass parsing fix and its small/valid controls.

[Rejected second-pass experiments](rejected-2026-10-29/README.md) preserve the
CSV and native encoder tradeoffs so they are not rediscovered as wins.
