+++
title = "Rust toolchain"
weight = 4
+++

# Rust toolchain

`ms` is implemented in Rust. Debug builds use Cranelift; optimized builds use pinned LLVM tools when available. The first native link downloads `lld`, and the first optimized build downloads `opt`, `llc` and `llvm-link`; later builds reuse the cache. See [linking and tool overrides](#differences-users-can-see). Release tags publish it (`release.yml` calls the [Rust distributions workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml) and uploads its six archives).

## Build and run

`rust-toolchain.toml` pins Rust 1.99.1 with `rustfmt` and `clippy`; install [rustup](https://rustup.rs) and cargo selects it. `rust-toolchain.toml` also installs the musl targets that Linux programs link against; Windows builds also need the `x86_64-pc-windows-gnullvm` or `aarch64-pc-windows-gnullvm` target (`rustup target add`). Building `ms` needs a C compiler (`ring` compiles C sources), the platform prerequisites below, and network access for dependencies. The native runtime (`ms-native`) is an explicit step: `make runtime` (`cargo xtask runtime`) builds it into `target/ms-native/libms_native.a`, and `ms-cli`'s build script only embeds that archive (or the one `MS_NATIVE_LIB` names), failing with this command when it is missing. Rerun it after changing `ms-rt`, `ms-rt-abi`, `ms-rt-hot`, or any `ms-std-*` crate.

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

`ms run tools/package.ms [-- OS ARCH]` builds the same binary with debug sections stripped and writes `dist/manuscript-rust-<os>-<arch>` as a `.tar.gz` (`.zip` on Windows) with a `.sha256` file. The workflow builds the six release targets natively, and every leg gates the check.

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
| `ms-clif` | MIR to Cranelift object code, line tables, perf map, and native linking with cached lld/LLVM tools and embedded startup files |
| `ms-rt`, `ms-rt-abi`, `ms-native` | Runtime (with the `ffi` and `glue` helpers the native crates build on), C-layout ABI types, and the static library embedded in `ms` |
| `ms-rt-hot` | The runtime's pure helpers (map probes, string compare and hash), also linked as LLVM IR into release programs so they inline |
| `ms-std-*` | One crate per native standard module, depending on `ms-rt` as an ordinary Rust crate |
| `ms-lower` | Checked HIR to MIR, including native standard calls |
| `ms-driver` | Manifest, lock, import resolution; module graph, entry rule, checking |
| `ms-build` | Lowering seam, optimization, native codegen and link |
| `ms-tooling`, `ms-lsp` | Lint, inspect, review, diagram; `search_symbol`, `guide`, docgen; language server |
| `ms-cli`, `ms-conform` | The `ms` binary; the conformance runner |

The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the pipeline, value layout, and runtime ABI rules. `unsafe` is confined as described in [development](development.md#rust-unsafe-boundary).

## Differences users can see

Behavior to know about:

- **Value semantics.** Values have one owner and move at their last use; `var` marks mutation at the declaration and the call (`f(var xs)`), and `.clone()` explicitly copies ordinary nested data; handle types can define cloning as sharing their underlying resource. Programs that relied on shared lists, records, or interface payloads, or on shallow `clone()`, behave differently. Cyclic structures cannot be built. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).
- **Source attribution.** Native builds emit DWARF line tables for file/line lookup, including optimized code. They do not describe variables, types, or inline call frames. `ms debug` and the debugger adapter are not part of the Rust `ms`; `ms profile` provides folded stacks, pprof, and a top report.
- **`ms emit` prints MIR.** Use `ms emit main.ms` or `ms emit ms.toml -o main.mir` to inspect lowered intermediate code. Native builds compile MIR to object code through Cranelift, or LLVM for release builds.
- **`ms build` reuses unchanged builds.** `ms-build` hashes the optimized module (file names and lines included), the build profile, the `ms` executable, the runtime archive, `--link` inputs, the codegen environment variables, the working directory and the output file name, and stores the finished executable (and the macOS `.dSYM`) in `<project>/.ms-cache/exe/<hash>`; the eight newest entries stay. A matching rebuild skips code generation and linking. `ms run` and `ms test` do not use it. `MS_CACHE=off` disables it and `MS_CACHE=verify` rebuilds and fails when the result differs from the cached executable; `MS_TIMINGS=1` prints phase times on stderr. See `proposals/incremental-builds.md`.
- **Release builds use cached LLVM tools when available.** `ms-clif` translates each Cranelift function to LLVM IR (`llvm_ir.rs`) and the pinned `opt` and `llc` (`default<O3>` and `-O3`, `Os` and `-O2` for MinSizeRel) optimize it, then the pinned `lld` links the objects side by side (no `clang` or `cc`); Cranelift still emits data, descriptors and `main`, and Debug builds stay on Cranelift. Fault traces and profiles keep their source frames because the runtime tables are rebuilt from LLVM's DWARF (`llvm_tables.rs`). A function with a loop over list elements, no calls in it and a single way out (no early `return` or `break`, which LLVM cannot vectorize) is also built for x86-64-v3 (AVX2, FMA) on x86-64, and a small dispatcher picks the copy by `msrt_cpu_level`; `MS_CPU_LEVEL=baseline` forces the baseline copy. `llc` aligns loops to 32 bytes on x86-64, so a small loop does not straddle a cache line depending on where the linker places the function. `MS_VECTORIZE=off` disables the loop and SLP vectorizers and the AVX2 copies. `MS_BACKEND=cranelift` opts out; `MS_LLVM_TOOLS` names a directory holding `opt`, `llc` and `llvm-link`. `ms` does not embed `opt`, `llc` and `llvm-link`, and Debug builds (Cranelift) never need them: the first Release build downloads the release pinned in `toolchain/lld.lock` with `ms`'s own HTTPS client (`link/fetch.rs`, honoring `HTTPS_PROXY`; about 70 MB, SHA-256 checked, no `curl` or `tar` needed) into `<cache>/ms/llvm/` and later builds reuse it. When the download fails (offline), that build prints one line and uses Cranelift; CI restores the directory from a cache keyed on `toolchain/lld.lock`. On Windows the IR targets the mingw-w64 triple.
- **Linking.** `ms` does not embed `lld`: the first link downloads the static `lld` pinned in `toolchain/lld.lock` (released by manuscript-lang/llvm-bundle, SHA-256 checked) into `<cache>/ms/lld/`; `MS_LLD` names a local one instead and skips the download. Building `ms` needs neither. Linux links static musl executables over the startup files and libc copied from the Rust toolchain by `crates/ms-clif/build.rs`, and the runtime is built for the musl target. macOS links against `.tbd` stubs generated from the imported symbols; it needs no SDK, and `dsymutil` (if present) writes `<output>.dSYM` beside the executable, which should stay with it for source lookup. Windows links with the same lld over llvm-mingw's startup object, CRT and import libraries (`sh toolchain/fetch-mingw.sh` fetches the pinned release into `target/llvm-bundle/mingw`; set `MS_MINGW` to use another copy), the runtime is built for `<arch>-pc-windows-gnullvm` with its clang (`rustup target add` it first), and DWARF stays in the image. No MSVC SDK is needed to link programs; building `ms` itself still uses the MSVC toolchain.
- **Build metadata.** `ms build -o app` writes `app.ms-build.json` beside the executable.
- **Concurrency.** [Task groups](../core-language/concurrency/task-groups.md) run cooperative work on one thread, [worker groups](../core-language/concurrency/workers.md) use isolated OS threads, and [process groups](../core-language/concurrency/process-groups.md) start child processes. Cancellation, faults and cleanup differ across these boundaries; see the guides for their contracts.
- **Exit codes.** A fault exits 67, SIGINT 130, SIGTERM 143; `ms run` and `ms test` return 128 plus the signal for a signalled child.
- **Math.** `@std/math` calls the host libm; results can differ between hosts in the last bit (for example `sin(2.0)`). `round` (ties toward positive infinity), `sign`, and `is_integer` are defined by the language.
- **`ms test --shuffle`** uses its own random generator, so orders differ from other shuffles; fixtures run once per test, not once per module.
- **Standard library.** Matching Rust std output is acceptable where Rust std covers the concept, so error texts and edge-case output can differ where the corpus does not pin them.
- **Windows.** The standard crates use Windows-specific behavior (synthetic errnos, emulated `pread`/`pwrite`, subset of `FileConstants`, `SendSignal` terminating the child); Windows and macOS builds gate CI like Linux.

Do not add code solely to reproduce older output where Rust std covers the concept.
