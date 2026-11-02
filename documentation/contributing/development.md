+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. `rust-toolchain.toml` pins Rust and `.node-version` pins Node. Setup needs Make and Internet access; the repository tools in `tools/` are Manuscript programs run by the `ms` that `make build` produces. Building `ms` needs a C compiler (`cc`); the first native link downloads the pinned `lld` into the cache (`MS_LLD` names a local one), and the first optimized build also fetches the LLVM tools. Linking with the packaged compiler needs no separate C compiler; see the [platform build requirements](rust-toolchain.md). Book work needs Hugo Extended 0.146.7 or newer.

```sh
make doctor
make verify
```

- `make doctor` reports missing prerequisites without downloading.
- `make verify` runs `make check` (`cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`), `make repo-check`, `make unit` (`cargo nextest run --workspace` and doc tests), `make docs-check`, and `make licenses-check`.
- `make runtime` (`cargo xtask runtime`) builds the native runtime into `target/ms-native/`. `ms-cli`'s build script only embeds that archive, so run it first (and after runtime changes; it also writes `ms_rt_hot.ll`, the pure runtime helpers that release builds inline, see [DESIGN.md](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#pure-and-stateful-runtime-code)) before any cargo command that compiles `ms-cli`, such as clippy, nextest, or `cargo build`; `make check`, `make unit`, and `make build` do it for you. In CI it runs once per Rust job, ahead of sccache-wrapped cargo calls, so the runtime's compiler outputs are cached like any other crate.
- `make build` produces `target/release/ms`; the Rust build details are in [Rust toolchain](rust-toolchain.md).
- `make fmt`, `make docs`, and `make licenses` write corrections and generated output explicitly.

`make repo-check` (the `ms-repo-check` crate) also caps multi-line Manuscript programs held in Rust string literals per file (`BASELINE` in `inline_source.rs`; the counts only go down), and rejects invalid syntax in any `stdlib/*.ms` file, nested matches in repository Manuscript sources, and Markdown fences (`manuscript`, `ms`, `text`), including untracked files Git does not ignore. Keep examples and remedies flat; see [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

- Allowance: a deliberate regression puts `# manuscript:allow-nested-match <reason>` before one inner match in a `tests/*.ms` fixture.
- Each allowance covers one match; implementation and documentation cannot opt out.

Complete validation:

```sh
make verify-full
```

It adds `make conform` (the conformance corpus), `make e2e` (every `tests/e2e/testdata` fixture), `make book-check`, and `make dist-check` (package the binary and run the archive on the hello example). Set `HUGO=/path/to/hugo` if it is not on PATH.

## Conformance

`make conform` builds the Rust `ms` and `ms-conform`, lints the corpus, and replays the run, check, and test phases of `tests/conformance/` against `ms`, excluding fixtures tagged `aliasing`, and the parse phase for every fixture. Known differences are listed in `tests/conformance/expect-fail.txt`. `CONFORM_SHARD=i/n` splits the run. See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

`make leak-check` builds the runtime with allocation counters (`ms-rt` feature `stats`, via `MS_RT_LIB`) and runs the corpus programs that finish normally, failing when any leaves live heap blocks at exit. Pass files to sweep instead (`target/release/ms run tools/leak-check.ms -- path.ms`). Run it after changing lowering, ownership, or runtime code; valgrind covers the native `ms-std-*` crates that use the system allocator.

`make count-check` runs `tests/ownership-counts/*.ms` in Debug and Release against the same counting runtime and compares the runtime's `ms-rt counts:` line (allocations, allocated bytes, runtime list copies and string clones) with each fixture's `# expect-debug:` / `# expect-release:` headers, and the program's stdout (cleanup order) with its `# expect-stdout:` lines. Lowering and optimizer passes legitimately change allocation counts, so the two builds carry separate expectations; a change that raises a count states why and updates the header in the same commit. Inline list clones allocate and copy without a runtime call, so `alloc_bytes` is the reliable copy signal.

Keep Manuscript source out of Rust strings. Diagnostics and run output belong in `tests/conformance/fixtures/snippets/` (`ms-conform record`) or `tests/e2e/testdata`; lowering expectations are `# expect-mir:` header comments on `crates/ms-build/tests/lower/*.ms`; a Rust test that drives a program (servers, signals, pipes) loads it with `include_str!` from a `.ms` file beside it. Rust tests keep to Rust internals.

Write source assertions with `@std/test/test.ms` and propagate their Results: `operation() | try expect_ok | try expect_equal(value)`. Fault messages are asserted in `.ms` tests with `expect_fault`. For callbacks that must be skipped, record invocations and assert that the record stays empty.

`make stdlib-bench` prints per-case ns/op for `bench/perf/stdlib` (`BENCHREPEATS`, `BENCHFILTER`); add cases as `bench` blocks in `bench/perf/stdlib/*_bench.ms` (`measure(ops, work)` times the work after untimed setup); `BENCHREPEATS` is the sample count. It is a profiling guide, not a gate. `make agent-bench-check` runs the agent benchmark oracle.

Complete tutorial fences carry a `manuscript-example` JSON comment giving `test` or `run`, arguments, and expected stdout (more fields in [common tasks](../learn/common-tasks.md)).

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

[CI/CD](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/cicd.yml) runs on PRs, merge groups, pushes to `main`, and by hand; the cache-maintenance workflow starts a manual run on `main` to refresh the caches when a push run ends, at most once an hour (its hourly schedule is best-effort). Superseded PR runs are cancelled; merge-group runs are not. Checkouts use the event's `github.sha`. [Language checks](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/test-language.yml) run the pinned linters, repository rules, license check, and the VS Code extension package in one job.

The account runs 20 jobs at once, so a pull request starts two jobs (`linux-amd64 · checks`, `linux-arm64 · checks`; no detect, language, book or aggregate job) and a push, merge group or manual run twelve Rust jobs plus the small ones. A push, merge group or manual run splits each platform (linux, darwin and windows on amd64 and arm64) into two parts on separate runners, named `tests` and `conformance` in the job list (`linux-amd64 · tests`); a pull request runs both parts in one job per Linux architecture, one workspace build and one runtime build per runner. The amd64 job also runs the language checks and the book build, and each job skips its Rust steps when the change touches only documentation, skills, proposals, extensions or Markdown. The `tests` part runs cargo-nextest, doc tests, debug-attribution tests (linux-amd64 also fmt and clippy) and the Cranelift corpus and fixtures where the platform runs them (linux-amd64, darwin-arm64, windows-amd64); the `conformance` part runs the frozen corpus and e2e fixtures and the gates (bundled-LLVM release build, source conformance, cancellation and ownership checks, the packaged `ms` on a hello project). Platforms without Cranelift put the gates in the `tests` part to balance the two. The slowest part sets the wall time. nextest, the corpus runner and the e2e runner (`E2E_JOBS` overrides the worker count) use every core. Pushes, merge groups and manual runs also run the language job, the book, and two aggregates. Each Rust part compiles through sccache and restores one sccache directory per platform and part (a pull request job restores part `a`'s; 2 GB cap, keyed on `Cargo.lock` and the toolchain), saved only by manual runs on `main`, which the cache-maintenance workflow starts at most hourly, each as a new entry that the prune workflow keeps instead of the previous one; it caches each compiler output, so `target/` is not saved and a changed crate rebuilds only itself. Documentation-only pull requests skip them. The **Rust checks** aggregate fails if any Rust job fails, is cancelled, or is skipped when Rust-relevant files changed.

Release tags package through [`rust-dist.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml), called from `release.yml`; every target gates there, and matching `v*` tags publish archives. Require **linux-amd64 · checks** and **linux-arm64 · checks** for PRs (the two jobs are the whole PR run). Merge groups and pushes still report **Build design book**, **Language checks / test**, and **Rust checks** (queue checks use `merge_group: checks_requested`); the aggregates fail if any dependency fails or is cancelled.

## Generate the standard library reference

`ms-docgen` (`crates/ms-tooling/src/guide`) reads the checker's registry from `stdlib/*.ms`, so signatures, bounds, fields, cases, and operations have one authority. Integration tests compare native conventions against it.

Generated references live in `.artifacts/docs/documentation/standard-library/reference/` and are mounted by Hugo. `website/static/stdlib.md` and `stdlib.json` (versioned, sorted schema) are generated and ignored by Git; `website/static/llms.txt` points to the plain-text API. Change source or generators, then run `make docs` and the book checks; never hand-edit generated output.

## Rust `unsafe` boundary

`unsafe` is confined to `crates/ms-rt` (raw memory behind the C ABI), the `crates/ms-std-*` C ABI shims, `crates/ms-rt-abi` (C-layout types), `crates/ms-cli/src/process.rs` (libc signals), and `crates/ms-cli/tests/terminal.rs` (pseudo-terminal test). The workspace denies `unsafe_code`, `unsafe_op_in_unsafe_fn` and unsafe blocks without a `// SAFETY:` comment, and `make repo-check` fails when any other Rust file uses `unsafe` or lifts the lint. Widening the allow-list in `crates/ms-repo-check/src/unsafe_boundary.rs` needs a reason in the change that does it.
