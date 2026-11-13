+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. `rust-toolchain.toml` pins Rust and `.node-version` pins Node. Use Make and a C compiler (`cc`) to build `ms`; repository tools in `tools/` then run with that compiler. Install the [source-build prerequisites](rust-toolchain.md#build-and-run) before running checks. Book work needs Hugo Extended 0.146.7 or newer. Application builds use [cached or locally configured linking tools](../developer-tooling/how-it-works.md#build-tools-and-local-setup).

```sh
make doctor
make verify
```

- `make doctor` first builds `ms`, then reports available and missing prerequisites. The doctor program itself does not download tools; its prerequisite build can fetch Cargo dependencies. If you already have a built compiler, run `target/release/ms run tools/doctor.ms` to inspect the environment directly.
- `make verify` runs `make check` (ABI-symbol validation, Rust formatting and clippy), `make repo-check`, `make workflow-check` (CI scheduling and deployment), `make bench-check` (benchmark sources and tool tests), `make unit` (workspace tests, doc tests and program-map tests), `make docs-check`, and `make licenses-check`.
- `make runtime` (`cargo xtask runtime`) builds the native runtime into `target/ms-native/`. `ms-cli`'s build script only embeds that archive, so run it first (and after runtime changes; it also writes `ms_rt_hot.ll`, the pure runtime helpers that release builds inline, see [DESIGN.md](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#pure-and-stateful-runtime-code)) before any cargo command that compiles `ms-cli`, such as clippy, nextest, or `cargo build`; `make check`, `make unit`, and `make build` do it for you. In CI it runs once per Rust job, ahead of sccache-wrapped cargo calls, so the runtime's compiler outputs are cached like any other crate.
- `make build` produces `target/release/ms`; the Rust build details are in [Rust toolchain](rust-toolchain.md).
- `make fmt`, `make docs`, and `make licenses` write corrections and generated output explicitly.

`make repo-check` (the `ms-repo-check` crate) also caps multi-line Manuscript programs held in Rust string literals per file (`BASELINE` in `inline_source.rs`; the counts only go down), and rejects invalid syntax in any `stdlib/*.ms` file, nested matches in repository Manuscript sources, and Markdown fences (`manuscript`, `ms`, `text`), including untracked files Git does not ignore. Keep examples and remedies flat; see [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

- Allowance: a deliberate regression puts `// manuscript:allow-nested-match <reason>` before one inner match in a `tests/*.ms` fixture.
- Each allowance covers one match; implementation and documentation cannot opt out.

The program-map tests run actual CLI data through the page's pure JavaScript functions; they do not boot a browser or DOM. After building the debug CLI, run `node --test tests/diagram/*.test.cjs` for this check alone. It uses `CARGO_TARGET_DIR` when set, or an explicit `MS_BIN` executable path.

For a focused edit, first run the test that exercises the changed behavior. Use the full gate before merging compiler or runtime changes:

```sh
make verify-full
```

It adds `make conform` (the conformance corpus, which includes the former end-to-end fixtures under `tests/conformance/fixtures/e2e/`), `make book-check`, and `make dist-check` (package the binary and run the archive on the hello example). Set `HUGO=/path/to/hugo` if it is not on PATH.

## Conformance

`make conform` builds the Rust `ms` and `ms-conform`, lints the corpus, and replays the run, check, and test phases of `tests/conformance/` against `ms`, excluding fixtures tagged `aliasing`, and the parse phase for every fixture. Known differences are listed in `tests/conformance/expect-fail.txt`. `CONFORM_SHARD=i/n` splits the run. `make conform-fast` is the quick local loop: all four phases with every program built by Cranelift, about 2.5 minutes against about 8 on 4 cores (measured 2026-11-13: the LLVM -O3 step is about 90% of a run or test fixture's time). Run `make conform` before merging; CI keeps the LLVM pass. See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

CI does not run `make leak-check`: `CONFORM_LEAKS=1 make conform` runs the corpus against the counting runtime, and the runner fails a `fuzz/run`, `e2e` or `examples` fixture that exits with live blocks. `make leak-check` builds the runtime with allocation counters (`ms-rt` feature `stats`, via `MS_RT_LIB`) and runs the corpus programs that finish normally and the `test` blocks of `tests/conformance/fixtures/e2e` (one count per test), failing when any leaves live heap blocks at exit. Pass files to sweep instead (`target/release/ms run tools/leak-check.ms -- path.ms`). Run it after changing lowering, ownership, or runtime code; valgrind covers the native `ms-std-*` crates that use the system allocator.

`make copy-check` builds the corpus programs and test fixtures with `MS_COPY_PROBE=1`, which makes the compiler print every `copy` of an object value (a closure, interface or runtime object, or a value holding one) left in the lowered code. Such a value has one owner and is duplicated only through `.clone()`, so each line names a lowering site to fix, and the sweep fails while any remain. `MS_COPY_PROBE=strict` makes a single build fail on them instead. Lowering itself always fails the build (an internal error naming the lowering site and source position) when a borrowed place reaches an owning position without a declared copy. Pass files to sweep instead (`target/release/ms run tools/copy-check.ms -- path.ms`).

`make drift-check` runs the corpus's run and test phases twice, with the LLVM release backend and with `MS_BACKEND=cranelift`, and fails when stdout, stderr or exit status differ (`ms-conform diff --env-a/--env-b` sets one side's environment). Measured 2026-11-06: 756 fixtures (541 run, 215 test, including the 400 fuzz programs) and the 4 aliasing-tagged ones, zero drift.

`make count-check` runs `tests/ownership-counts/*.ms` in Debug and Release against the same counting runtime and compares the runtime's `ms-rt counts:` line (allocations, allocated bytes, runtime list copies and string clones) with each fixture's `# expect-debug:` / `# expect-release:` headers, and the program's stdout (cleanup order) with its `# expect-stdout:` lines. Lowering and optimizer passes legitimately change allocation counts, so the two builds carry separate expectations; a change that raises a count states why and updates the header in the same commit. Inline list clones allocate and copy without a runtime call, so `alloc_bytes` is the reliable copy signal.

`make resource-matrix` generates one program per standard operation that stores, returns or discards a one-owner resource, per call form (direct, or a method value called later) and argument form (temporary or named), and runs each one the checker accepts in Debug and Release. Each program must exit normally and close every resource it made exactly once (`mk` prints `made-N`, `close` prints `closed-N`); a combination the checker rejects is skipped. The tool also lists the declarations of List, Map, Set, Optional and Result (`ms search_symbol prelude.<Type> --json`) and fails when an operation that mentions a type parameter has neither a row in `operations()` nor a reason in `exempt()` in `tools/resource-matrix.ms`.

`make close-matrix` is the sibling for language constructs. It generates one program per resource shape (a bare resource, an Optional, a List, a Map, a record, an enum, a Result, a list of Optionals) and construct that ends or moves its life: scope end, early return, `?` error, loop exits, reassignment, by-value arguments (direct, method, method value, function value, interface, generic, later `?`), returned owners, closure capture and escape, promise capture and cancellation, explicit close, `if v := x`, `match` and destructuring. The oracle is the same: exit normally and close every made resource once, in Debug and Release. Add a construct to `constructs()` in `tools/close-matrix.ms` when a new construct moves, drops or closes a value; `-- rejects` lists the combinations the checker refuses.

Each crate with several integration-test files links them as one binary: add a file under `tests/` and declare it as a module in that crate's `tests/main.rs` (run it with `cargo nextest run -p <crate> --test it <module>::`).

Keep Manuscript source out of Rust strings. Diagnostics and run output belong in `tests/conformance/fixtures/snippets/` (`ms-conform record`) or `tests/conformance/fixtures/e2e`; lowering expectations are `# expect-mir:` header comments on `crates/ms-build/tests/lower/*.ms`; a Rust test that drives a program (servers, signals, pipes) loads it with `include_str!` from a `.ms` file beside it. Rust tests keep to Rust internals.

Write source assertions with `@std/test/test.ms` and propagate their Results: `operation() | expect_ok? | expect_equal(value)?`. Fault messages are asserted in `.ms` tests with `expect_fault`. For callbacks that must be skipped, record invocations and assert that the record stays empty.

`make stdlib-bench` prints per-case ns/op for `bench/perf/stdlib` (`BENCHREPEATS`, `BENCHFILTER`); add cases as `bench` blocks in `bench/perf/stdlib/*_bench.ms` (`measure(ops, work)` times the work after untimed setup); `BENCHREPEATS` is the sample count. It is a profiling guide, not a gate. `make agent-bench-check` runs the agent benchmark oracle.

Complete tutorial fences carry a `manuscript-example` JSON comment giving `test` or `run`, arguments, and expected stdout (more fields in [cookbook](../cookbook/command-line.md)).

`make dist` builds a single-binary archive in `dist/` with `tools/package.ms`.

## Preview and publish the book

Author guides in `documentation/`; standard-library descriptions live above declarations in `stdlib/*.ms`. Site config, assets, and the vendored theme live in `website/`. Lexical rules live in `extensions/vscode/syntaxes/manuscript.tmLanguage.json`.

```sh
make docs
make book-check
make book
hugo --source website server --bind 127.0.0.1 --port 4000 --renderToMemory
```

- `make docs-check` validates source documentation and description policy without writing generated Markdown.
- `make docs` rebuilds the ignored tree in `.artifacts/docs/`, removing obsolete pages.
- `make book-check` generates that tree, then validates links, highlighting, and published pages under a project URL prefix.
- `make book` writes the site to ignored `.artifacts/book/`. It passes `--cleanDestinationDir` so removed modules do not survive.
- `make docs-coverage` writes `.artifacts/stdlib-doc-coverage.json`, inventorying every public declaration and member. The same quality and new-gap gate runs in `make docs` and `make docs-check`: describe behavior, units, defaults, errors, or ownership, not names or signatures.

The book uses vendored Hugo Book v13; put styling in `website/assets/_custom.scss`, behavior in `docs.js`, overrides in `website/layouts/`, never the theme. `.msversion` supplies release labels; older sites go in `website/data/docs_versions.toml`. See [maintenance](maintenance.md) for pins and releases.

## Continuous integration

[`cicd.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/cicd.yml) runs the checks. Pull requests use the Linux matrix and the required `Platform checks` result. Scheduled and manual runs cover the full platform matrix.

- **Pull request: the Linux legs.** linux-amd64 and linux-arm64 each run `tests`, three `conformance` shards (`linux-amd64 · conformance 0`) and, on linux-arm64, `gates`, the same jobs `main` runs, with the language checks and the book inside linux-arm64 gates. linux-amd64 runs the Cranelift corpus in the conformance shards and leaves the gates to linux-arm64. Measured 2026-11-13, an unsharded linux-arm64 conformance job took 29 minutes against 8 for `tests`, so `CONFORM_SHARD=i/3` splits the corpus. A leg whose gates run elsewhere starts its `gates` job and skips every step. A newer commit cancels the earlier run. A documentation-only change (documentation, skills, proposals, extensions, Markdown) skips the Rust steps.
- **`main` every 30 minutes and manual runs: all six platforms** (linux, darwin and windows on amd64 and arm64), each split into the same tests, gates and conformance-shard jobs as a pull request's, and finishes in the time of its slowest job. A push to `main` starts nothing: a cron run every 30 minutes checks the newest commit and does nothing when an earlier scheduled run already checked it (the `Main changed` job), so a burst of merges costs one run, not one per merge. A failure on `main` is fixed or reverted there. A manual run takes an `os` input (`all`, `linux`, `darwin`, `windows`) to run one platform's legs, for example to check a platform-sensitive branch. Manual runs do not replace the scheduled six-platform check, even at the same commit. Scheduled and manual `all`/`linux` runs on `main` deploy Pages from the book linux-arm64 builds.
- **Ruleset:** require `Platform checks`, the sum of the platform legs.
- Only scheduled and manual runs on `main` save the sccache caches, each as a new entry that cache-maintenance's prune keeps instead of the previous one. Each job restores one sccache directory per platform, keyed on `Cargo.lock` and the toolchain (1500 MB cap); it caches compiler outputs, so `target/` is not saved.

[`rust-checks`](https://github.com/manuscript-lang/manuscript/blob/main/.github/actions/rust-checks/action.yml) holds the Rust steps both workflows share. Part `a` (`tests`) builds the workspace once and runs cargo-nextest, doc tests and debug-attribution tests (linux-amd64 also fmt and clippy), then the Cranelift corpus where the platform runs them (linux-amd64, darwin-arm64, windows-amd64). Parts `b0` to `b2` (`conformance`) each run a third of the frozen corpus (which holds the former end-to-end fixtures) and, on legs that run Cranelift there (linux-amd64, windows-amd64), a third of the Cranelift corpus. Part `g` (`gates`) runs the gates (bundled-LLVM release build, source conformance, ownership checks, the packaged `ms` on a hello project); on the Cranelift-in-conformance legs the gates run in part `a`. The leak sweep runs inside the LLVM corpus run, and the slowest Rust tests (`mutation`, `golden`) are split into parallel shards, because on a 4-core runner one long test or serial sweep set the job's length. nextest and the corpus runner use every core. Checkouts use the event's `github.sha`. The [language checks](https://github.com/manuscript-lang/manuscript/blob/main/.github/actions/language-checks/action.yml) (repository rules, license check, the VS Code extension package) and the book run inside the linux-arm64 job.

Release tags package through [`rust-dist.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml), called from `release.yml`; every target gates there, and matching `v*` tags publish archives.

## Generate the standard library reference

`ms-docgen` (`crates/ms-tooling/src/guide`) reads the checker's registry from `stdlib/*.ms`, so signatures, bounds, fields, cases, and operations have one authority. Integration tests compare native conventions against it.

Generated references live in `.artifacts/docs/documentation/standard-library/reference/` and are mounted by Hugo. `website/static/stdlib.md` and `stdlib.json` (versioned, sorted schema) are generated and ignored by Git; `website/static/llms.txt` points to the plain-text API. Change source or generators, then run `make docs` and the book checks; never hand-edit generated output.

## Rust `unsafe` boundary

`unsafe` is confined to the paths listed in `crates/ms-repo-check/src/unsafe_boundary.rs`: runtime and C ABI implementation, process signals, pseudo-terminal tests, and the interner/session lifetime boundary. The standalone allocation counters in `bench/perf/binding-flags/main.rs` and `storage.rs` are exact-file exceptions: Rust's `GlobalAlloc` interface requires `unsafe`; these counters forward every operation to `System` and record requested sizes with atomics, without inspecting allocation contents. They do not enter production builds. The workspace denies `unsafe_code`, `unsafe_op_in_unsafe_fn` and unsafe blocks without a `// SAFETY:` comment. `make repo-check` checks Rust files under `crates/` and `bench/` against the allow-list. Widening that list needs a reason in the change that does it.
