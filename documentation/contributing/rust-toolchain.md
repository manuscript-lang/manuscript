+++
title = "Rust toolchain"
weight = 4
+++

# Rust toolchain

The Rust and Cranelift implementation of `ms` is replacing the Go one. Release tags publish the Rust `ms` (`release.yml` calls the workflow below and uploads its six archives); the Go `ms` stays only until it is deleted. The Rust `ms` builds from the same checkout and is packaged by the [Rust distributions workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml). The Go code stays until the Rust `ms` passes the conformance corpus.

## Build and run

`rust-toolchain.toml` pins Rust 1.99.1 with `rustfmt` and `clippy`; install [rustup](https://rustup.rs) and cargo selects it. Linking generated programs needs a system C compiler driver (`cc`) on `PATH`. Nothing else is required: the native runtime (`ms-native`) is built and embedded by `ms-cli`'s build script.

```sh
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

`sh scripts/package-rust.sh [OS ARCH]` builds the same binary with debug sections stripped and writes `dist/manuscript-rust-<os>-<arch>` as a `.tar.gz` (`.zip` on Windows) with a `.sha256` file. The workflow builds the six release targets natively, and every leg gates the check.

`.cargo/config.toml` forces frame pointers: fault traces and `ms profile` walk them. On Windows, fault reporting uses native unwind records to reach the first generated source frame, then follows contiguous generated callers. Attribution stops at a native callback or generated glue boundary; complete mixed native/generated stack unwinding is not supported.

## Checks

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo nextest run --workspace
cargo test --workspace --doc
```

CI runs these as **Rust format and clippy**, **Rust tests** (two nextest partitions plus doc tests), and **Rust corpus** (four shards). Pull requests that only change documentation, the website, blog, proposals, skills, extensions, or Markdown skip them.

The conformance corpus in `tests/conformance/` holds programs with expectations first recorded from the Go `ms` and now frozen. `make conform-rust` replays it against the Rust binary (CI shards it four ways); `make conform-oracle` re-checks it against the Go binary locally until the Go code is removed. See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

Runtime memory safety is checked under Miri, which needs a nightly toolchain and is not part of CI:

```sh
rustup toolchain install nightly --profile minimal -c miri
MIRIFLAGS=-Zmiri-ignore-leaks cargo +nightly miri test -p ms-rt --lib
```

Under Miri the allocator takes its arena from the heap in place of `mmap` (and is 64 MiB, not 16 GiB), `ms-rt` skips tests that need files, processes, signals or context-switching assembly, and `-Zmiri-ignore-leaks` forgives that arena. `crates/ms-rt/src/model_tests.rs` runs the collections and strings against `Vec` and `String` models with a fixed seed, so a failure repeats.

## Crates

| Crate | Responsibility |
| --- | --- |
| `ms-syntax` | Lexer, parser, syntax tree, formatter |
| `ms-check` | Resolution, types, generics, contracts, effects, cleanup, ownership; typed HIR; diagnostics |
| `ms-mir` | HIR lowering, ownership elaboration, optimizer, verifier |
| `ms-clif` | MIR to Cranelift object code, line tables, perf map |
| `ms-rt`, `ms-rt-abi`, `ms-native` | Runtime, C-layout ABI types, and the static library embedded in `ms` |
| `ms-std-*` | One crate per native standard module |
| `ms-lower` | Checked HIR to MIR, including native standard calls |
| `ms-project`, `ms-driver` | Manifest, lock, import resolution; module graph, entry rule, build and link |
| `ms-tooling`, `ms-guide`, `ms-lsp` | Lint, inspect, review, diagram; `search_symbol`, `guide`, docgen; language server |
| `ms-cli`, `ms-conform` | The `ms` binary; the conformance runner |

The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the pipeline, value layout, and runtime ABI rules. `unsafe` is confined as described in [development](development.md#rust-unsafe-boundary).

## Differences users can see

The Rust `ms` accepts the same `.ms` source and `ms.toml` manifests, with these differences.

- **Value semantics.** Values have one owner and move at their last use; `var` marks mutation at the declaration and the call (`f(var xs)`), and `.clone()` makes an explicit deep copy (to be spelled `.copy()`). Programs that relied on shared lists, records, or interface payloads, or on shallow `clone()`, behave differently. Cyclic structures cannot be built. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).
- **No debugger.** `ms debug` and the debugger adapter are not part of the Rust `ms`; use `ms profile` (folded stacks, pprof, top report) or `perf` on any `ms build` output, which keeps frame pointers, DWARF line tables, and a perf map.
- **`ms emit` is not implemented.** It reports that the Go `ms` is needed. The Rust backend produces object code, not Go source.
- **Linking uses the system `cc`.** A bundled linker is planned.
- **Build metadata.** `ms build -o app` writes `app.ms-build.json` beside the executable.
- **No concurrency runtime.** Tasks are cooperative and single-threaded; cancellation exists for signals and shutdown only.
- **Exit codes.** A fault exits 70, SIGINT 130, SIGTERM 143; `ms run` and `ms test` return 128 plus the signal for a signalled child.
- **Math.** `@std/math` calls the host libm; results can differ from Go in the last bit (for example `sin(2.0)`). `round` (ties toward positive infinity), `sign`, and `is_integer` are defined by the language.
- **`ms test --shuffle`** uses its own random generator, so orders differ from the Go `ms`; fixtures run once per test, not once per module.
- **Standard library.** Matching Rust std output is acceptable where Rust std covers the concept, so error texts and edge-case output can differ from Go where the corpus does not pin them.
- **Windows.** The standard crates follow Go's Windows behavior (synthetic errnos, emulated `pread`/`pwrite`, subset of `FileConstants`, `SendSignal` terminating the child); Windows and macOS builds gate CI like Linux.

Anything the Rust `ms` does only to match the Go output is recorded and tracked for removal after cutover. Do not add code solely to reproduce Go output where Rust std covers the concept.
