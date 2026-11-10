# Warm language-server query latency

This suite measures the production Rust LSP implementation, including complete
hover response construction. It does not measure generated Manuscript code or
compare different languages. See [the dated evidence](results-2026-11-10.md).

The query harness adapts the [October 31 LSP suite](../lsp/README.md) to the
current explicit name/session APIs. The latest suite-wide baseline is
[October 28](../baseline-2026-10-28.md); its workloads do not measure LSP queries.
Historical timings on other hosts are context, never the comparison baseline.

Build identical copies of this harness against the before and after source
worlds with the repository-pinned toolchain:

```sh
cargo +1.99.1 build --release --locked \
  --manifest-path bench/perf/lsp-query/Cargo.toml --target-dir /tmp/lsp-before
```

Use a separate target directory for the candidate. The `ms-lsp-server` binary
uses `crates/ms-lsp/src/main.rs` unchanged, including its supervisor and worker.
Both binaries use the repository release settings: opt-level 3, debug 1, panic
abort, and frame pointers. No runtime archive or Manuscript backend is involved.

```sh
python3 bench/perf/lsp-query/compare.py \
  /tmp/lsp-before/release/ms-lsp-query-perf \
  /tmp/lsp-after/release/ms-lsp-query-perf /tmp/paired.csv 9
python3 bench/perf/lsp-query/wire.py \
  /tmp/lsp-before/release/ms-lsp-server \
  /tmp/lsp-after/release/ms-lsp-server /tmp/wire.csv 7
```

The Python scripts are host-side subprocess/protocol orchestration with no
third-party packages. The measured queries execute Rust production code.
They require Linux affinity/resource accounting. This does not gate or skip
any cross-platform correctness test.

`compare.py` calibrates a common repetition count for each case to about 30 ms
on the baseline, then alternates AB/BA process order. Each process performs an
untimed warm-up. Full JSON and input-size fingerprints must match both variants
on every sample. Hover-name is a lookup-only control; it is not full hover.
Completion includes private request analysis and JSON construction. Symbol and
hover queries exclude initial checking/index construction. Timing includes
serialization and fingerprint consumption. All samples, including slower
controls, remain in the CSV. RSS and page faults include setup and are not
query-allocation counters. No instruction counts are claimed when unavailable.

The fixed isolated `/tmp/ms-lsp-query-isolated` directory must be empty; source
lives only in the open document. This prevents completion from discovering
unrelated `/tmp` files. `wire.py` similarly uses the empty
`/tmp/ms-lsp-query-wire-isolated` directory. Run one suite at a time.

The wire suite opens valid source, warms the server/index and each query, then
measures 30 sequential request/response round trips per sample. It checks every
complete payload against the paired baseline and pins independently expected
hover contents. Full payloads are saved alongside the CSV. It covers tiny,
ordinary and large files, documented functions, unchanged method/receiver
fallbacks, LF/CRLF and a same-line emoji. Transport timings include Python JSON
framing/parsing and pipes; startup/checking is recorded separately. These are
warm editor-protocol measurements, not cold filesystem or graphical-editor
latencies.

For the recorded matched comparison, start both source copies at
`754aa75a3c5fb66a54c19047cf9f2bb45d1a9db4`, copy this harness to each, and apply
[hover.patch](results-2026-11-10/hover.patch) only to the after copy. Evidence
branches do not themselves need to carry the production change. Optional
`LSP_BENCH_NS` changes standalone sample length; `LSP_BENCH_CASES` selects
comma-separated `mode:count:shape` cases. The wire runner accepts
`LSP_WIRE_ROUNDS`, `LSP_WIRE_CASES` (`count:newline`) and `LSP_WIRE_QUERIES`
(comma-separated query names). The exact longer reruns are in `commands.txt`.
