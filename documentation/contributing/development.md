+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. `.go-version` pins the SDK and `.node-version` pins Node. Setup needs Make, curl, tar with xz, a SHA-256 utility, and Internet access. Editor and book work need Hugo Extended 0.146.7 or newer. Race checks need a C compiler; macOS debugging needs Xcode command line tools.

```sh
make setup
make doctor
make verify
```

- `make setup` installs verified Go and pinned linters; `make doctor` reports missing prerequisites without downloading.
- `make verify` runs read-only format/vet, lint, workflow/shell lint, repository invariants, fast unit tests, checked tutorial examples, documentation validation, and license freshness. It builds no native conformance executables.
- `make check` and `make repo-check` reject invalid syntax in any `stdlib/*.ms` file, reporting file, line, and column.
- `make fmt`, `make docs`, and `make licenses` write corrections and generated output explicitly.

`make repo-check` also rejects nested matches in repository Manuscript sources, Markdown fences (`manuscript`, `ms`, `text`), and Go source strings, including untracked files Git does not ignore. Keep examples and remedies flat; see [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

- Allowance: a deliberate regression puts `# manuscript:allow-nested-match <reason>` before one inner match in a `tests/*.ms` fixture, or `// manuscript:allow-nested-match <reason>` before a source literal in a Go `_test.go` file.
- Each allowance covers one match or literal; implementation and documentation cannot opt out.
- Dynamically built Go strings need consumer tests; the guard reads source only.

Complete native validation:

```sh
make verify-full
```

It adds coverage, native conformance, race checks, fuzzing, strict book checks, and a standalone distribution test. Set `HUGO=/path/to/hugo` if it is not on PATH. `make build` creates the self-contained `ms`. Run `make payload` before invoking Go directly in a fresh checkout; an unprepared build fails at the embed input rather than using a system toolchain.


## Rust toolchain

The Rust `ms` builds with cargo, not Make: `cargo build --release --locked -p ms-cli` produces `target/release/ms`, and `sh scripts/package-rust.sh` packages it. Rust changes run `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo nextest run --workspace`; `make conform-rust` replays the frozen conformance corpus against the Rust `ms`. Setup, crates, and differences from the Go `ms` are in [Rust toolchain](rust-toolchain.md). The Go commands in this guide stay authoritative until cutover.

## Conformance and coverage

- `make coverage` runs the Go suite, native conformance fixtures, and complete tutorial modules from Markdown, instrumenting dependency packages. Reports land in `.artifacts/coverage/`. Race-checked packages run without coverage because instrumentation makes timing tests flaky; native subprocesses are judged by observable expectations.
- The end-to-end suite builds one CLI and reuses it. Accepted fixtures run their test blocks, rejected cases verify diagnostics, and transcripts check evaluation order, cleanup, signals, host operations, and module boundaries. Use `make e2e E2EFLAGS=-count=1` for a fresh run; native subprocesses ignore ambient Go configuration.
- `make stdlib-check` requires a fixture in `tests/e2e/testdata/stdlib/*.ms` for every public standard module (`make verify` includes it). `make stdlib-test E2EFLAGS=-count=1` executes them; run one with `ms test <fixture>`.

`make stdlib-bench` prints per-case ns/op for `bench/perf/stdlib` (`BENCHREPEATS`, `BENCHFILTER`); add cases in `bench/perf/stdlib/src/*.ms` with `bench(name, ops, body)`. It is a profiling guide, not a gate.

Complete tutorial fences carry a `manuscript-example` JSON comment giving `test` or `run`, arguments, and expected stdout (more fields in [common tasks](../learn/common-tasks.md)). `make examples-check` checks them without lowering; coverage runs them natively. Run `MANUSCRIPT_EXAMPLES_NATIVE=1 toolchain/go/bin/go test ./tests/examples -count=1` to execute them directly.




`make fuzz` fuzzes strict parsing, editor recovery, and compilation for ten seconds each; set `FUZZTIME=1m` for more. Add an observable regression before calling a failure resolved.

`make dist` builds a single-binary archive in `dist/`; `sh scripts/package.sh <os> <arch>` targets Linux, macOS, or Windows on AMD64 or ARM64. `make dist-check` runs a copied binary outside the checkout with empty caches, no Go on PATH, and downloads disabled; compilation, source tools, LSP, debug builds, and profiles must work.

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
- `make book-check` generates that tree, then validates links, highlighting, API signatures, downloads, and obsolete routes under a project URL prefix.
- `make book` writes the site to ignored `.artifacts/book/`. Use `--cleanDestinationDir` so removed modules do not survive.
- `make docs-coverage` writes `.artifacts/stdlib-doc-coverage.json`, inventorying every public declaration and member. The same quality and new-gap gate runs in `make docs` and `make docs-check`: describe behavior, units, defaults, errors, or ownership, not names or signatures.



The book uses vendored Hugo Book v13; put styling in `website/assets/_custom.scss`, behavior in `docs.js`, overrides in `website/layouts/`, never the theme. `.msversion` supplies release labels; older sites go in `website/data/docs_versions.toml`. `pkg/tooling/docgen/description_backlog.json` may only shrink. See [maintenance](maintenance.md) for pins and releases.

## Continuous integration

[CI/CD](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/cicd.yml) runs on PRs, merge groups, and pushes to `main`. Superseded PR runs are cancelled; merge-group runs are not. Checkouts use the event's `github.sha`. [Language checks](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/test-language.yml) run in parallel, each unit once:

- The Go suite in three shards via `scripts/ci-test.sh`: in-process packages under race, the rest with coverage.
- Static checks, the bundled CLI, fuzzing, extension/debugger integration, and macOS/Windows host checks.

The Rust jobs (one job for fmt, clippy, cargo-nextest, and doc tests, plus the conformance corpus in two shards) share `Swatinem/rust-cache`, saved only from `main`. Documentation-only pull requests skip them. The **Rust checks** aggregate fails if any Rust job fails, is cancelled, or is skipped when Rust-relevant files changed.

The [distribution workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/release.yml) packages and verifies all six targets on every PR and merge group, with no path filters. Manual runs produce artifacts; matching `v*` tags publish archives. Require **Build design book**, **Language checks / test**, **Rust checks**, and **Distribution checks** for PRs and merge groups (queue checks use `merge_group: checks_requested`); the aggregates fail if any dependency fails, is skipped, or is cancelled.


## Generate the standard library reference

`scripts/docgen` reads the checker's registry from pinned `stdlib/*.ms`, so signatures, bounds, fields, cases, and operations have one authority. Integration tests compare native conventions against it.

Generated references live in `.artifacts/docs/documentation/standard-library/reference/` and are mounted by Hugo. `website/static/stdlib.md` and `stdlib.json` (versioned, sorted schema) are generated and ignored by Git; `website/static/llms.txt` points to the plain-text API. Change source or generators, then run `make docs` and the book checks; never hand-edit generated output.


`make conformance` builds the CLI and uses [scripts/conformance.ms](https://github.com/manuscript-lang/manuscript/blob/main/scripts/conformance.ms) to discover and run core, multi-file project, and standard-library fixtures through `ms test --json`. Each file gets its own compiler graph and process. The runner rejects empty, failed, or incomplete reports and accounts for explicit skips; its own report-validation and shard tests also run through `ms test`. `make test`, `make e2e`, and `make coverage` include this native pass. The CI job that builds the bundled CLI runs it once, separately from the Go shards.

`make stdlib-check` checks the dedicated Manuscript stdlib fixtures and requires a fixture for every public standard module; `make verify` includes it. `make stdlib-test` runs only the standard-library suite. Select or shard the complete suite with `make conformance CONFORMANCE_SUITE=core CONFORMANCE_SHARD=0 CONFORMANCE_SHARDS=3`; run every shard index to cover the suite. The core suite also executes the hello and tooling-demo example tests and both compact formatter fixtures. Fixtures live in `tests/e2e/testdata/accept/*.ms`, `tests/e2e/testdata/projects/*/conformance_test.ms`, and `tests/e2e/testdata/stdlib/*.ms`; select individual cases directly with `ms test <fixture> --test '<file>::<name>'`.

Write source assertions with `@std/testing.ms` and propagate their Results: `operation() | try expect_ok | try expect_equal(expected: value)`. Helpers used for assertions also return Result. Physical `.ms` tests use Result errors and run through `ms test`. Fault messages are asserted in `.ms` tests with `expect_fault`; Go string fixtures remain only where Go must check fault frames and line numbers, process status, cleanup, CLI output, or compiler diagnostics. For callbacks that must be skipped, record invocations and assert that the record stays empty. The separate `TestRunnerFaultIsolation` Go regression launches intentional escaping faults and checks continuation, cleanup, and fresh host roots; it is not the conformance dispatcher. Go tests also retain source coverage checks, compiler diagnostics, native process protocols, and implementation-level tests.

## Rust `unsafe` boundary

`unsafe` is confined to `crates/ms-rt` (raw memory behind the C ABI), `crates/ms-rt-abi` (C-layout types) and `crates/ms-cli/src/process.rs` (libc signals). The workspace denies `unsafe_code`, `unsafe_op_in_unsafe_fn` and unsafe blocks without a `// SAFETY:` comment, and `make repo-check` fails when any other Rust file uses `unsafe` or lifts the lint. Widening the allow-list in `scripts/repo-check/unsafe_boundary.go` needs a reason in the change that does it.
