# Checker type operations investigation, 2026-11-10

Historical initial inspection. The owner subsequently authorized isolated Rust
installation; see [the completed continuation](README.md). The status below is
preserved as the initial state, not the final outcome.

Status: blocked before measurement. No current performance defect was demonstrated,
no production patch was made, and no issue or PR was opened. This is an investigation
record, not a benchmark result or evidence that the checker has no performance problems.

## Revision and environment

- Local checkout: `d4485491cec0ac1faf08da067e0c31aa02d0e902`.
- Live main read through GitHub:
  [`d1ea6ce161ed9e5bd1af5c3b4edd8ca0b8f4b251`](https://github.com/manuscript-lang/manuscript/commit/d1ea6ce161ed9e5bd1af5c3b4edd8ca0b8f4b251).
- Linux 6.18.57 x86_64, AMD EPYC 9V74, five visible CPUs (0–4), shared VM.
- Required Rust toolchain: 1.99.1 from `rust-toolchain.toml`.
- No `cargo`, `rustc`, or `ms` found on PATH; no repository `target/release/ms`.
  Conventional `/home/agent/.cargo`, `/root/.cargo`, `/usr/local/cargo`, and
  `/opt/rust` tool locations did not provide an available toolchain.
- No toolchain installation, cache relocation, protected-cache write, or policy
  workaround was attempted.

The four assigned local files match live-main Git blob identities exactly:

| File under `crates/ms-check/src/` | Git blob |
| --- | --- |
| `type_keys.rs` | `3ba35fd62d57418753e5975a3c9b017ff0f60036` |
| `types.rs` | `70aa3987c2c071dbb7fa3a8f2a4e07d9a7613e14` |
| `tytable.rs` | `3e9d9a894c98b5fcdeec23ad9209450860951bdb` |
| `inference.rs` | `040dca0c645d977c166f058c2d1b318000fae4c0` |

Compared GitHub file metadata at the exact live commit with:

```sh
git hash-object crates/ms-check/src/type_keys.rs crates/ms-check/src/types.rs crates/ms-check/src/tytable.rs crates/ms-check/src/inference.rs
```

## Findings from source and history

- `type_keys.rs` is compiled only under `cfg(test)` in `lib.rs`. Optimizing its
  string construction cannot improve production checker throughput.
- `TyTable` already interns dense structural rows. A query bounds ordinary work
  before deduplicating completed shared subtrees; ordinary leaf rows bypass that
  machinery. This was shipped in
  [#2560](https://github.com/manuscript-lang/manuscript/pull/2560).
- `same` already bounds repeated successful structural comparisons. A blanket
  pointer-equality shortcut would change existing behavior for incomplete function
  results: `structural_equality_keeps_missing_results_and_late_mismatches` pins it.
  See [#2325](https://github.com/manuscript-lang/manuscript/pull/2325).
- `sub_walk` already allocates argument/parameter vectors only after a changed
  child and preserves concrete sharing. Unbound variables must still snapshot
  their mutable bounds/default metadata, even with an empty binding map.
  [#2267](https://github.com/manuscript-lang/manuscript/pull/2267) records the
  previous optimization and rejected slower candidates. Its microbenchmark gains
  did not establish an end-to-end checker speedup.
- Inference's `parameter_type` indexes the resolved parameter directly.
  `inference_type_resolved` already uses the bounded type-graph search.
- Remaining recursive transformation work in `sub_walk`, `required_walk` when
  omission metadata is present, and `unify_at` is a possible profiling target,
  not a new demonstrated performance defect. Existing snapshot, callable-mode,
  and omission-permission semantics preclude blindly memoizing every result.

Open/recent PR and issue searches were read before source investigation.
[#3481](https://github.com/manuscript-lang/manuscript/pull/3481) is merged;
[#3351](https://github.com/manuscript-lang/manuscript/pull/3351) remains open.
No overlapping open checker-type PR appeared in that read. Historical findings
were treated as historical evidence, not current measurements.

## Baseline and build attempt

Read the latest all-suite [dated baseline](../baseline-2026-10-28.md), the
[November 9 performance investigation](../perf-bash-2026-11-09.md), and
[compile-time evidence](../../compile-time/README.md), whose latest section is
dated November 6. Runtime kernel numbers do not establish checker operation cost;
the compile-time evidence is also from another machine/revision.

The prescribed production build was attempted from the repository root:

```text
$ make build
cargo xtask runtime
make: cargo: No such file or directory
make: *** [Makefile:32: runtime] Error 127
```

Process exit status: 2. The runtime/compiler build did not start. There are no
generated benchmark inputs, execution checksums, timing samples, instruction
counts, or page-fault measurements from this investigation.

## What remains

Resume in an approved environment with the pinned compiler/build prerequisites
and release `ms`. Recheck live main and overlapping work, then profile complete
`ms check` workloads before choosing a change. Use ordinary and shared generic
types, accepted and rejected input, small controls and N/2N/4N sizes. Preserve
exact diagnostics/exits and retain raw paired samples, revisions, build settings,
instruction counts and page faults. Changes to substitution also need the existing
independent-snapshot controls; equality needs incomplete-result controls.

No native tests, workspace checks, conformance/e2e runs, platform CI, or independent
patch review ran: there is no implementation patch to validate. Publication and
merge remain unperformed. The blocker is an unavailable build prerequisite, not
an approval denial or a demonstrated checker regression.
