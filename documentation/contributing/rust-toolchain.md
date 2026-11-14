+++
title = "Rust toolchain"
weight = 4
+++

# Rust toolchain

Build the compiler, run its tests, and package native releases. `ms` is implemented in Rust; its native backends are Cranelift and LLVM. For application builds with an installed compiler, see [build levels](../developer-tooling/builds/build-levels.md) and [local tool setup](../developer-tooling/how-it-works.md#build-tools-and-local-setup). Release tags publish six platform archives through [`rust-dist.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml).

## Build and run

`rust-toolchain.toml` pins Rust 1.99.1 with `rustfmt` and `clippy`; install [rustup](https://rustup.rs) and cargo selects it. `rust-toolchain.toml` also installs the musl targets that `ms build --static` programs link against; Windows builds also need the `x86_64-pc-windows-gnullvm` or `aarch64-pc-windows-gnullvm` target (`rustup target add`). Building `ms` needs a C compiler (`ring` compiles C sources), the platform prerequisites below, and the pinned dependencies, downloaded during setup or supplied through the Cargo cache. The native runtime (`ms-native`) is an explicit step: `make runtime` (`cargo xtask runtime`) builds it into `target/ms-native/libms_native.a`, and `ms-cli`'s build script only embeds that archive (or the one `MS_NATIVE_LIB` names), failing with this command when it is missing. Rerun it after changing `ms-rt`, `ms-rt-abi`, `ms-rt-hot`, or any `ms-std-*` crate.

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

The last command prints:

```text
Arguments: 2
```

Use this built binary when reproducing a compiler issue, so the result reflects your checkout.

`ms run tools/package.ms [-- OS ARCH]` builds the same binary with debug sections stripped and writes `dist/manuscript-rust-<os>-<arch>` as a `.tar.gz` (`.zip` on Windows) with a `.sha256` file. The workflow builds the six release targets natively, and every leg gates the check.

`.cargo/config.toml` forces frame pointers: fault traces and `ms profile` walk them. On Windows, fault reporting uses native unwind records to reach the first generated source frame, then follows contiguous generated callers. Attribution stops at a native callback or generated glue boundary; complete mixed native/generated stack unwinding is not supported.

## Checks

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo nextest run --workspace
cargo test --workspace --doc
```

CI splits each platform into tests and conformance jobs. Pull requests run the Linux legs; scheduled and manual runs cover the full platform matrix. Documentation-only changes skip Rust steps. See [continuous integration](development.md#continuous-integration) for the current jobs and gates.

The conformance corpus in `tests/conformance/` holds programs with frozen expected output. `make conform` replays it against the Rust binary (CI runs it on linux-amd64, darwin-arm64, and windows-amd64). See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

Runtime memory safety is checked under Miri, which needs a nightly toolchain and is not part of CI:

```sh
rustup toolchain install nightly --profile minimal -c miri
MIRIFLAGS=-Zmiri-ignore-leaks cargo +nightly miri test -p ms-rt --lib
```

Under Miri the allocator takes its reservation from the heap in place of `mmap` (and is 64 MiB, not 256 GiB), `ms-rt` skips tests that need files, processes, signals or context-switching assembly, and `-Zmiri-ignore-leaks` forgives that reservation. `crates/ms-rt/src/model_tests.rs` runs the collections and strings against `Vec` and `String` models with a fixed seed, so a failure repeats.

## Crates

| Crate | Responsibility |
| --- | --- |
| `ms-syntax` | Lexer, parser, syntax tree, formatter |
| `ms-check` | Resolution, types, generics, contracts, effects, cleanup, ownership; typed HIR; diagnostics |
| `ms-mir` | MIR representation, ownership elaboration, optimizer, verifier, text format, interpreter |
| `ms-mir-llvm` | MIR to LLVM IR text: functions, glue, descriptors, vtables and globals; depends only on `ms-mir` and `ms-rt-abi` |
| `ms-clif` | MIR to Cranelift object code, line tables, perf map, and native linking with cached lld/LLVM tools and embedded startup files |
| `ms-rt`, `ms-rt-abi`, `ms-native` | Runtime (with the `ffi` and `glue` helpers the native crates build on), C-layout ABI types, and the static library embedded in `ms` |
| `ms-rt-hot` | The runtime's pure helpers (map probes, string compare and hash), also linked as LLVM IR into release programs so they inline |
| `ms-std-*` | One crate per native standard module, depending on `ms-rt` as an ordinary Rust crate |
| `ms-lower` | Checked HIR to MIR, including native standard calls |
| `ms-driver` | Manifest, lock, import resolution; module graph, entry rule, checking |
| `ms-build` | Lowering seam, optimization, native codegen and link |
| `ms-tooling`, `ms-lsp` | Lint, inspect, review, diagram; `search_symbol`, agent skill, docgen; language server |
| `ms-cli`, `ms-conform` | The `ms` binary; the conformance runner |

The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the pipeline, value layout, and runtime ABI rules. `unsafe` is confined as described in [development](development.md#rust-unsafe-boundary).

## Native builds and platform support {#differences-users-can-see}

The following details describe the compiler's generated artifacts and platform integration. Language semantics are defined in the [language reference](../core-language/_index.md).

### Optimization

`ms-mir-llvm` writes LLVM IR straight from MIR (`mir_llvm`, `glue_llvm`, assembled by `llvm_ir.rs`) and `ms-clif` runs the pinned `opt` and `llc` (`default<O3>` and `-O3`, `Os` and `-O2` for MinSizeRel) optimize it, then the pinned `lld` links the objects side by side (no `clang` or `cc`); the LLVM modules define the data and descriptors, Cranelift still emits the fault and profile tables and `main`, and Debug builds stay on Cranelift. Fault traces and profiles keep their source frames because the runtime tables are rebuilt from LLVM's DWARF (`llvm_tables.rs`). The code targets the baseline CPU of each architecture; LLVM does the vectorizing and the build emits no per-CPU copies or dispatchers. `llc` aligns loops to 32 bytes on x86-64, so a small loop does not straddle a cache line depending on where the linker places the function. `MS_VECTORIZE=off` disables the loop and SLP vectorizers.

`MS_BACKEND=cranelift` opts out; `MS_LLVM_TOOLS` names a directory holding `opt`, `llc` and `llvm-link`. See [build tools and local setup](../developer-tooling/how-it-works.md#build-tools-and-local-setup) for downloads, caches and fallback behavior. On Windows the IR targets the mingw-w64 triple.

### Platform linking

Use a compatible local `lld` through `MS_LLD`, or let `ms` cache the SHA-256-verified version pinned in `toolchain/lld.lock`. Building `ms` itself does not require this linker; linking Manuscript programs does.

**Linux.** Linux links dynamic executables that run on glibc 2.28 or newer: the runtime is built for `<arch>-unknown-linux-gnu` and defines `_start` itself (`crates/ms-native`), and lld links it, with the bundled static `libunwind.a`, against stub glibc libraries generated from `toolchain/glibc/<arch>.symbols` (`toolchain/glibc/generate.sh` regenerates them from glibc 2.28's ABI lists), so the host's glibc, `libc6-dev` and a C compiler are never used. `--static` instead links a static musl executable over the startup files and libc copied from the Rust toolchain by `crates/ms-clif/build.rs`, with a second runtime built for the musl target (`libms_native_musl.a`); `ms` embeds both.

**macOS.** macOS links against `.tbd` stubs generated from the imported symbols; it needs no SDK, and `dsymutil` (if present) writes `<output>.dSYM` beside the executable, which should stay with it for source lookup.

**Windows.** Windows links with the same lld over llvm-mingw's startup object, CRT and import libraries (`sh toolchain/fetch-mingw.sh` fetches the pinned release into `target/llvm-bundle/mingw`; set `MS_MINGW` to use another copy), the runtime is built for `<arch>-pc-windows-gnullvm` with its clang (`rustup target add` it first), and DWARF stays in the image. No MSVC SDK is needed to link programs; building `ms` itself still uses the MSVC toolchain.

### Source attribution and inspection

Native builds emit DWARF line tables for file/line lookup, including optimized code. They do not describe variables, types, or inline call frames. `ms profile` provides folded stacks, pprof, and a top report; see [native debugging](../developer-tooling/debugging/debugger-integration.md).

Use `ms emit main.ms` or `ms emit ms.toml -o main.mir` to inspect lowered MIR. For checked source relationships, use [the interactive HTML code map](../developer-tooling/implementation.md#interactive-code-map).

### Build cache and metadata

`ms build` keys an entry on the build profile, input and output paths, working directory, the build settings (`BuildOptions`, parsed once from the `MS_*` variables in `ms-cli`) and the size and modification time of the `ms` executable, the runtime override and `--link` files. The entry lists every source file (and `ms.toml`) with its size and modification time. While all still match, the next `ms build` copies the stored executable (and macOS `.dSYM`) to the output without loading, checking or compiling anything. Entries live in `<dir of the input>/.ms-cache/build`; the eight newest stay. Nothing is hashed, so a new file that would shadow an imported one is not noticed until a listed file changes. `ms run` and `ms test` do not use it. `MS_CACHE=off` disables it and `MS_CACHE=verify` rebuilds and fails when the result differs from the cached executable; `MS_TIMINGS=1` prints phase times on stderr; `MS_DUMP_CLIF=1` prints the Cranelift IR of every function before it is compiled (Cranelift builds only); `MS_CLIF_VERIFY=1` runs Cranelift's IR verifier, which is on by default only in builds of `ms` with debug assertions. See `proposals/incremental-builds.md`.

`ms build -o app` also writes `app.ms-build.json` beside the executable.

### Runtime and platform behavior

- Values follow the [ownership rules](../core-language/types/references.md); concurrency follows the [promise and stream contracts](../core-language/concurrency/_index.md).
- A fault exits 67, SIGINT 130, SIGTERM 143; `ms run` and `ms test` return 128 plus the signal for a signalled child.
- `@std/math` calls the host libm; results can differ between hosts in the last bit (for example `sin(2.0)`). `round` (ties toward positive infinity), `sign`, and `is_integer` are defined by the language.
- `ms test --shuffle` uses a seeded generator for repeatable ordering. Each selected test and repetition runs with its own fixture; see [testing](../learn/testing.md#shared-setup-and-teardown).
- Windows standard modules use synthetic errnos, emulated `pread`/`pwrite`, a subset of `FileConstants`, and `SendSignal` terminating the child. Windows and macOS run in the full scheduled/manual matrix; pull requests run Linux. See [continuous integration](development.md#continuous-integration).
