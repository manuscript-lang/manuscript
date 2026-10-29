# Workload comparison validation, 2026-10-29

This fixes measurement accounting, not generated code. At baseline
`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`, a controlled Rust producer printing
different output still returned a successful workload comparison: only the last
Manuscript/Go outputs were compared. An incorrect earlier trial could also be
overwritten by a correct final trial. The new runner rejects either case and
publishes no table. The real-wrapper regression additionally covers a later
workload failing after an earlier workload succeeded, including retained output.

The documented relative `MS=./target/release/ms` invocation now resolves before
the build changes directory. Invalid repeat counts fail before tools run. Go's
`-buildvcs=false` matches the kernel/program runners and avoids a VCS-stamping
failure encountered in this isolated worktree. Producer algorithms are unchanged.

## Native release controls

Compiler source: the exact baseline above, built with Rust 1.99.1
(`58cf8f9c3 2026-10-13`); compiler SHA-256
`d1767f5fb967bab6c8aa14590875b81b3750c257295393b622a4acd4bd3617b9`.
Linux x86-64, kernel 6.18.55, glibc 2.41, Intel Xeon Platinum 8573C, shared host.
Go 1.24.7 and `rustc -O` build the hand-written references. Builds are outside
the timers. LLVM 23.1.1 tool versions and hashes are in the raw environment record.
The [invocation receipt](validation-2026-10-29/llvm-invocations.jsonl)
records the actual LLVM `-passes=default<O3>` and `llc -O3 -align-loops=32` calls,
for both explicit `--build-type Release` and the default build type. Release use
is observed here; neither a release-built CLI nor the build flag alone proves it.
This is the optimizer used for generated functions; Cranelift also emits support
objects. The receipt entries have no per-build labels, so their association to
explicit/default builds relies on the session's build sequence. The retained
`ms-build.json` says `cranelift`; that field was not used as backend proof or
reinterpreted by this lane.

Two existing reference programs, each at four input sizes, were run in seven
rotating paired rounds after one untimed run of every version. All 224 timed
processes and 32 warm-ups exited successfully and matched independently generated
expected bytes. CSV groups contain valid decimal amounts, a quoted category and
a rejected row. Calculator groups contain precedence, parentheses, negative
division, division by zero and syntax errors. Small inputs expose startup cost;
larger inputs exercise the same workload at scale. The timer surrounds only the
prebuilt process, including startup and I/O. Validation and hashing follow it.

Milliseconds, **minimum / median / maximum** of seven runs:

| program | groups | explicit Release | default | Go | Rust |
|---|---:|---:|---:|---:|---:|
| CSV | 1 | 0.669 / 0.800 / 1.818 | 0.848 / 1.028 / 1.926 | 1.233 / 2.337 / 3.972 | 1.804 / 2.191 / 2.487 |
| CSV | 1,000 | 1.560 / 2.381 / 4.137 | 1.606 / 2.378 / 51.788 | 1.861 / 2.310 / 4.126 | 1.783 / 2.463 / 3.728 |
| CSV | 10,000 | 9.100 / 10.542 / 15.137 | 9.298 / 12.039 / 70.388 | 6.205 / 10.038 / 14.686 | 4.515 / 5.114 / 9.702 |
| CSV | 100,000 | 91.555 / 99.114 / 143.738 | 91.584 / 101.797 / 104.790 | 61.679 / 67.187 / 88.449 | 28.890 / 33.184 / 39.664 |
| calculator | 1 | 0.607 / 1.394 / 2.184 | 0.778 / 0.940 / 1.282 | 1.281 / 1.868 / 2.742 | 1.810 / 2.490 / 3.297 |
| calculator | 1,000 | 1.610 / 1.973 / 6.742 | 1.582 / 1.862 / 19.839 | 2.665 / 3.354 / 4.338 | 5.056 / 6.007 / 19.355 |
| calculator | 10,000 | 9.669 / 11.284 / 15.057 | 8.706 / 10.894 / 15.888 | 15.109 / 18.244 / 24.857 | 37.023 / 40.892 / 50.863 |
| calculator | 100,000 | 94.539 / 98.504 / 122.506 | 83.013 / 111.793 / 245.469 | 137.323 / 159.893 / 264.901 | 372.299 / 449.825 / 833.453 |

Keep the outliers: these distributions do not establish a configuration speedup.
No compiler/configuration change is proposed from them. Cross-language gaps are
observations, not newly attributed causes. Compiler/lowering/backend investigations
were excluded from this lane. Windows and macOS were not measured.

The new `measure.py` also passed native integration checks on both largest inputs
with three rotating trials each. Its output checks and retained identities passed.
This is separate from the table above; no timing improvement is claimed from
changing the timer or adding warm-ups.

## Reproduce

Build the compiler from the pinned baseline using the repository's Rust-toolchain
guide (`cargo xtask runtime`, then `cargo build --release --locked -p ms-cli`).
Use a separate output directory, for example `.artifacts/release-config-controls`.
For each of `c03-csv-group-sum` and `c05-calculator`, copy the three reference
sources from `bench/agent/challenges/<name>/solutions/` into `<out>/<name>/`:
Manuscript as `ms/src/main.ms`, Go as `go/main.go`, Rust as `rs/main.rs`; copy
`bench/agent/templates/ms/ms.toml` into `ms/`. Build these exact binaries:

```sh
# MS is an absolute path to the compiler; run each command in its language directory.
"$MS" build ms.toml --build-type Release -o app
"$MS" build ms.toml -o default-app
go mod init x
go build -buildvcs=false -o app .
rustc -O -o app main.rs
```

Use the same pinned LLVM tools and retain their build invocations, as in the
receipt above. Run the [archived driver](validation-2026-10-29/measure-controls.py)
with the prepared output directory, absolute compiler path and source SHA:

```sh
python3 bench/perf/workloads/validation-2026-10-29/measure-controls.py \
    .artifacts/release-config-controls "$MS" \
    4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192
```

It regenerates every input and expected output, checks producer status/bytes on
every invocation, rotates the four versions, and writes `native-controls.json`.
The [recorded raw samples](validation-2026-10-29/native-controls.json) retain full
timings, counts, input/output hashes, all four binary hashes and environment details.
The driver cannot identify a backend from timings; its receipt path is a pointer
to independently collected build evidence. An optional fourth argument names the
real LLVM tool directory to record its binary hashes and versions.
