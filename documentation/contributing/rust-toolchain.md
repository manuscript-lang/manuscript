+++
title = "Rust toolchain"
weight = 4
+++

# Rust toolchain

`ms` is implemented in Rust. Debug builds use Cranelift and Linux release builds use LLVM through bundled `opt`, `llc` and `lld`, with no `clang`. Release tags publish it (`release.yml` calls the [Rust distributions workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml) and uploads its six archives).

## Build and run

`rust-toolchain.toml` pins Rust 1.99.1 with `rustfmt` and `clippy`; install [rustup](https://rustup.rs) and cargo selects it. `rust-toolchain.toml` also installs the musl targets that Linux programs link against; Windows builds also need the `x86_64-pc-windows-gnullvm` or `aarch64-pc-windows-gnullvm` target (`rustup target add`). Building `ms` needs a C compiler (`ring` compiles C sources) and a static `lld` (see Linking below); running `ms` needs neither. Nothing else is required: the native runtime (`ms-native`) is built and embedded by `ms-cli`'s build script.

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

CI runs these in one **Rust** job per platform; linux-amd64 runs fmt, clippy, nextest, doc tests, and the corpus. Pull requests that only change documentation, the website, blog, proposals, skills, extensions, or Markdown skip them.

The conformance corpus in `tests/conformance/` holds programs with frozen expected output. `make conform` replays it against the Rust binary (CI runs it on linux-amd64, darwin-arm64, and windows-amd64). See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

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
| `ms-mir` | MIR representation, ownership elaboration, optimizer, verifier, text format, interpreter |
| `ms-clif` | MIR to Cranelift object code, line tables, perf map |
| `ms-rt`, `ms-rt-abi`, `ms-native` | Runtime, C-layout ABI types, and the static library embedded in `ms` |
| `ms-std-*` | One crate per native standard module |
| `ms-lower` | Checked HIR to MIR, including native standard calls |
| `ms-project`, `ms-driver` | Manifest, lock, import resolution; module graph, entry rule, build and link |
| `ms-tooling`, `ms-guide`, `ms-lsp` | Lint, inspect, review, diagram; `search_symbol`, `guide`, docgen; language server |
| `ms-cli`, `ms-conform` | The `ms` binary; the conformance runner |

The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the pipeline, value layout, and runtime ABI rules. `unsafe` is confined as described in [development](development.md#rust-unsafe-boundary).

## Differences users can see

Behavior to know about:

- **Value semantics.** Values have one owner and move at their last use; `var` marks mutation at the declaration and the call (`f(var xs)`), and `.clone()` makes an explicit deep copy (to be spelled `.copy()`). Programs that relied on shared lists, records, or interface payloads, or on shallow `clone()`, behave differently. Cyclic structures cannot be built. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).
- **Source attribution.** Native builds emit DWARF line tables for file/line lookup, including optimized code. They do not describe variables, types, or inline call frames. `ms debug` and the debugger adapter are not part of the Rust `ms`; `ms profile` provides folded stacks, pprof, and a top report.
- **`ms emit` prints MIR.** Use `ms emit main.ms` or `ms emit ms.toml -o main.mir` to inspect lowered intermediate code. Native builds compile MIR to object code through Cranelift, or LLVM for Linux release builds.
- **Release builds use the bundled LLVM tools on Linux.** `ms-clif` translates each Cranelift function to LLVM IR (`llvm_ir.rs`) and the bundled `opt` and `llc` (`default<O3>` and `-O3`, `Os` and `-O2` for MinSizeRel) optimize it, then the bundled `lld` merges the objects (no `clang` or `cc`); Cranelift still emits data, descriptors and `main`, and Debug builds stay on Cranelift. Fault traces and profiles keep their source frames because the runtime tables are rebuilt from LLVM's DWARF (`llvm_tables.rs`). `MS_BACKEND=cranelift` opts out; `MS_LLVM_TOOLS` names a directory holding other `opt` and `llc`. `opt` and `llc` are embedded gzipped (about 50 MB together) when `scripts/fetch-lld.sh` fetched them before the build; an `ms` built without them, or off Linux, uses Cranelift for Release.
- **Linking.** `ms` embeds a pinned static `lld`. Building `ms` needs it: set `MS_LLD` to one, or run `sh scripts/fetch-lld.sh` (downloads the release pinned in `scripts/lld.lock` and checks its SHA-256). Linux links static musl executables over the startup files and libc copied from the Rust toolchain by `crates/ms-clif/build.rs`, and the runtime is built for the musl target. macOS links against `.tbd` stubs generated from the imported symbols; it needs no SDK, and `dsymutil` (if present) writes `<output>.dSYM` beside the executable, which should stay with it for source lookup. Windows links with the same lld over llvm-mingw's startup object, CRT and import libraries (`sh scripts/fetch-mingw.sh` fetches the pinned release into `target/llvm-bundle/mingw`; set `MS_MINGW` to use another copy), the runtime is built for `<arch>-pc-windows-gnullvm` with its clang (`rustup target add` it first), and DWARF stays in the image. No MSVC SDK is needed to link programs; building `ms` itself still uses the MSVC toolchain.
- **Build metadata.** `ms build -o app` writes `app.ms-build.json` beside the executable.
- **No concurrency runtime.** Tasks are cooperative and single-threaded; cancellation exists for signals and shutdown only.
- **Exit codes.** A fault exits 70, SIGINT 130, SIGTERM 143; `ms run` and `ms test` return 128 plus the signal for a signalled child.
- **Math.** `@std/math` calls the host libm; results can differ between hosts in the last bit (for example `sin(2.0)`). `round` (ties toward positive infinity), `sign`, and `is_integer` are defined by the language.
- **`ms test --shuffle`** uses its own random generator, so orders differ from other shuffles; fixtures run once per test, not once per module.
- **Standard library.** Matching Rust std output is acceptable where Rust std covers the concept, so error texts and edge-case output can differ where the corpus does not pin them.
- **Windows.** The standard crates use Windows-specific behavior (synthetic errnos, emulated `pread`/`pwrite`, subset of `FileConstants`, `SendSignal` terminating the child); Windows and macOS builds gate CI like Linux.

Do not add code solely to reproduce older output where Rust std covers the concept.
