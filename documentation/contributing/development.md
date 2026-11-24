+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. `.node-version` pins Node. `ms` is built with CMake, Ninja and clang (`cmake --preset ci`, see [src/README.md](https://github.com/manuscript-lang/manuscript/blob/main/src/README.md)); repository tools in `tools/` then run with that `ms`. Book work needs Hugo Extended 0.146.7 or newer. Application builds use [cached or locally configured linking tools](../developer-tooling/how-it-works.md#build-tools-and-local-setup).

The debugger display helpers in `tools/debugger/` are Python (gdb and lldb embed it). Their decoding test, `display_helper_decoding_matches_the_layouts`, needs Python 3 as `python3` or `python`. It fails, not skips, without Python, and `make doctor` reports it. Every CI runner image (Linux, macOS and Windows, both architectures) has it.

```sh
make doctor
make verify
```

- `make doctor` first builds `ms`, then reports available and missing prerequisites (git, tar, cmake, ninja, clang, a C compiler, Python, Node, Hugo). If you already have a built compiler, run `.artifacts/build/ci/src/cli/ms run tools/doctor.ms` to inspect the environment directly.
- `make verify` runs `make repo-check`, `make bench-check` (benchmark sources and tool tests), `make docs-check`, and `make licenses-check`. `ctest --preset ci` runs the C tests and `cmake --build --preset ci --target lint` runs `ms_lint` (banned calls, layering).
- `make build` configures and builds the `ci` preset into `.artifacts/build/ci/src/cli/ms`; `cmake --preset release` builds the release `ms` that CI packages.
- `make fmt`, `make docs`, and `make licenses` write corrections and generated output explicitly.

`make repo-check` runs `tools/repo-check.ms` with the built `ms` (it also runs in pull request CI): `ms fmt --check` over the repository's `.ms` files, `ms lint --syntax` for nested matches in `.ms` files and Markdown fences (`manuscript`, `ms`, `text`; a `// manuscript:allow-nested-match <reason>` line before a match allows a fixture), the `.msversion` calendar version and the extension pin, the `ci.yml` triggers, the standard-library rules in `tools/stdlib-rules.ms` (an `options` or `limits` parameter has a default, no stream-shaped method names, methods follow their type, every `src/stdlib/internal` extern is used; `tools/optional-defaults-allowed.txt` and `tools/stream-names-allowed.txt` only shrink), and the license inventory. Keep examples and remedies flat; see [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

- Allowance: a deliberate regression puts `// manuscript:allow-nested-match <reason>` before one inner match in a `tests/*.ms` fixture.
- Each allowance covers one match; implementation and documentation cannot opt out.

The program-map tests run actual CLI data through the page's pure JavaScript functions; they do not boot a browser or DOM. After `make build`, run `node --test tests/docs/diagram/*.test.cjs` for this check alone. It uses the CLI built in `.artifacts/build/ci`, or the executable at `MS_BIN`.

For a focused edit, first run the test that exercises the changed behavior. Use the full gate before merging compiler or runtime changes:

```sh
make verify-full
```

It adds `make conform` (the conformance corpus, which includes the former end-to-end fixtures under `tests/conformance/fixtures/e2e/`), `make book-check`, and `make dist-check` (package the binary and run the archive on the hello example). Set `HUGO=/path/to/hugo` if it is not on PATH.

## Conformance

`make conform` builds `ms` and replays the run, check, and test phases of `tests/conformance/` against it (`tools/conform-run.ms`), excluding fixtures tagged `aliasing`, and the parse phase for every fixture. Known differences are listed in `tests/conformance/expect-fail.txt`. `CONFORM_SHARD=i/n` splits the run. `make conform` runs all four phases and `tools/conform.ms lint`. `make conform-release` replays the run and test phases with the Release build (CI replays Debug); it runs nightly. `ms run tools/conform.ms -- <command>` has the other corpus commands (`list`, `stats`, `lint`, `retag`, `diff`, `fuzz-gen`, `fuzz`, `harvest`; see the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md)).

See the [corpus guide](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md).

The counting runtime is a separate build: `cmake --preset stats && cmake --build --preset stats` compiles the runtime with `MS_STATS` into `.artifacts/build/stats`, and its `ms` makes every program print `ms-rt live blocks at exit: N` (and `ms-rt counts: allocs=… list_copies=… string_clones=…`) on standard error; `MS_PARK_COUNT=1` adds `ms-rt parks: N`, `MS_CANCEL_AT_PARK=k` cancels the k-th park, and `MS_STATS_TRACE=1` prints the allocation site of each live block (resolve the addresses with `addr2line -e <executable>`). `make leak-check` runs the corpus programs that finish normally and the `test` blocks of `tests/conformance/fixtures/e2e` against it and fails when any leaves live heap blocks; `make cancel-sweep` cancels each test at every park; `make count-check` compares `tests/checks/ownership-counts` with the `// expect-debug:` and `// expect-release:` headers; `make ownership-fuzz` runs random move/borrow/closure programs. The tools build the preset themselves (`tools/lib.ms` `use_stats_runtime`). CI does not run them. Design: [stats variant](../../design/proposals/c-runtime-stats-variant.md).

`MS_POISON_SLOTS=1` makes the compiler write a volatile `0xDD` fill over a shared stack cell right after the instruction that reads its occupant last (`mir_cell_conflicts` reports the deaths, `emit_poison_fills` writes them), so a view or pointer that outlives its slot reads garbage in every build instead of depending on what the optimizer reuses the cell for. Use it when a result differs between Debug and Release, and run the corpus with it after changing slot sharing or a runtime function that returns a pointer into its argument (`make poison-check`). It changes the generated code and is part of the build options, so cached builds do not mix.

`make copy-check` builds the corpus programs and test fixtures with `MS_COPY_PROBE=1`, which makes the compiler print every `copy` of an object value (a closure, interface or runtime object, or a value holding one) left in the lowered code. Such a value has one owner and is duplicated only through `.clone()`, so each line names a lowering site to fix, and the sweep fails while any remain. `MS_COPY_PROBE=strict` makes a single build fail on them instead. Lowering itself always fails the build (an internal error naming the lowering site and source position) when a borrowed place reaches an owning position without a declared copy. Pass files to sweep instead (`target/release/ms run tools/copy-check.ms -- path.ms`).


`make count-check` runs `tests/checks/ownership-counts/*.ms` in Debug and Release against the same counting runtime and compares the runtime's `ms-rt counts:` line (allocations, allocated bytes, runtime list copies and string clones) with each fixture's `# expect-debug:` / `# expect-release:` headers, and the program's stdout (cleanup order) with its `# expect-stdout:` lines. Lowering and optimizer passes legitimately change allocation counts, so the two builds carry separate expectations; a change that raises a count states why and updates the header in the same commit. Inline list clones allocate and copy without a runtime call, so `alloc_bytes` is the reliable copy signal.

`make resource-matrix` generates one program per standard operation that stores, returns or discards a one-owner resource, per call form (direct, or a method value called later) and argument form (temporary or named), and runs each one the checker accepts in Debug and Release. Each program must exit normally and close every resource it made exactly once (`mk` prints `made-N`, `close` prints `closed-N`); a combination the checker rejects is skipped. The tool also lists the declarations of List, Map, Set, Optional and Result (`ms search_symbol prelude.<Type> --json`) and fails when an operation that mentions a type parameter has neither a row in `operations()` nor a reason in `exempt()` in `tools/resource-matrix.ms`.

`make close-matrix` is the sibling for language constructs. It generates one program per resource shape (a bare resource, an Optional, a List, a Map, a record, an enum, a Result, a list of Optionals) and construct that ends or moves its life: scope end, early return, `?` error, loop exits, reassignment, by-value arguments (direct, method, method value, function value, interface, generic, later `?`), returned owners, closure capture and escape, promise capture and cancellation, explicit close, `if v := x`, `match` and destructuring. The oracle is the same: exit normally and close every made resource once, in Debug and Release. Add a construct to `constructs()` in `tools/close-matrix.ms` when a new construct moves, drops or closes a value; `-- rejects` lists the combinations the checker refuses.

`make stress-sched` builds a separate `ms` (`target/stress`) whose runtime has the `sched-stress` feature (the shipped runtime does not read `MS_SCHED_STRESS`), then runs the e2e stdlib tests with `MS_SCHED_STRESS=1`: a promise never starts on its creator and the first idle thread takes it, so one-in-N timing bugs fail every run. A file that fails under stress but passes without it fails the target; `STRESS_CHANGED=<ref>` runs only fixtures changed since `<ref>`. The nightly job on main runs it; pull request CI does not yet. Promises pinned to their creator (a live native stream, the terminal) stay on it. Do not run `ms-rt` unit tests with it set; some assert placement.


Keep Manuscript source out of C strings. Diagnostics and run output belong in `tests/conformance/fixtures/snippets/` or `tests/conformance/fixtures/e2e` (record with `ms run tools/conform-run.ms -- --record`).

Write source assertions with `@std/test/test.ms` and propagate their Results: `operation() | expect_ok? | expect_equal(value)?`. Fault messages are asserted in `.ms` tests with `expect_fault`. For callbacks that must be skipped, record invocations and assert that the record stays empty.

`make stdlib-bench` prints per-case ns/op for `bench/perf/stdlib`. `BENCHREPEATS` sets the sample count per case and `BENCHFILTER` narrows the cases. Add cases as `bench` blocks in `bench/perf/stdlib/*_bench.ms` (a `fixture` built by `make_fixture` keeps setup out of the timing). It is a profiling guide, not a gate.


Complete tutorial fences carry a `manuscript-example` JSON comment giving `test` or `run`, arguments, and expected stdout (more fields in [cookbook](../cookbook/command-line.md)).

A snippet that leaves names free is marked `"mode":"fragment"`. It is parsed only, unless the marker lists the free names as parameters, `"given":["raw: String"]`, in which case it is type-checked too: its imports and every standard name it uses must resolve, and its names must resolve and its calls must type-check. A `"context"` string adds declarations the snippet assumes, such as a type or helper. `"mode":"error"` expects `ms check` to fail, and `"contains"` names the message it must show. Every `manuscript` fence in `documentation/` needs a marker; use a `text` fence for pseudo-code. Prefer `given` for new fragments.

`make dist` packages with `cmake --build --preset ci --target dist` (`manuscript-<os>-<arch>.tar.gz`, `.zip` on Windows: `bin/ms` and `lib/ms/` with the runtime archives, startup files and the pinned `opt`, `llc` and `lld` of `cmake/toolchain/lld.lock`); `--target dist-smoke` unpacks it with an empty `PATH` and builds, runs and tests the hello example. The six-platform CI runs both and uploads the archive.

## Preview and publish the book

Author guides in `documentation/`; standard-library descriptions live above declarations in `src/stdlib/*.ms`. Site config, assets, and the vendored theme live in `website/`. Lexical rules live in `extensions/vscode/syntaxes/manuscript.tmLanguage.json`.

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

[`ci.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/ci.yml) runs the checks. Pull requests use the Linux matrix and the required `Platform checks` result. Scheduled and manual runs cover the full platform matrix.

- **Pull request: the Linux legs.** linux-amd64 and linux-arm64 each build the `ci` preset, run `ctest`, `lint`, `dist-smoke`, `repo-check`, `docs-check` and the conformance corpus; the book and the extension package build alongside, and the `Time budget` job fails a run over ten minutes. A newer commit cancels the earlier run.
- **`main` every six hours and manual runs: all six platforms** (linux, darwin and windows on amd64 and arm64), which also warms the caches pull requests restore and publishes the book to Pages. A failure on `main` is fixed or reverted there. A manual run takes a `platforms` input (`all` or `linux`); off `main` it always runs the two Linux legs.
- **Ruleset:** require `Platform checks`, the sum of the platform legs.


[`nightly-safety.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/nightly-safety.yml) runs `make cancel-sweep`, `make poison-check`, `make view-matrix`, `make stress-sched` and `make perf-counts` on `main` every night and on demand. `perf-counts` runs four suite programs under callgrind and opens an issue naming the commit range when one executes more than 3% more instructions than `bench/perf/counts.txt`; refresh the file with `ms run tools/perf-counts.ms -- --update` when a cost is deliberate. A failure is a bug to file and fix at its cause.

Release tags package through [`dist.yml`](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/dist.yml), called from `release.yml`: each platform builds with the `release` preset (Linux inside manylinux_2_28 so `ms` and the programs it links keep the glibc 2.28 floor), assembles `manuscript-<os>-<arch>` with the `dist` target and runs `dist-smoke`; every target gates there, and matching `v*` tags publish archives. `release-rehearsal.yml` runs the same jobs plus the installers on any branch without publishing.

## Generate the standard library reference

`tools/docgen.ms` renders the snapshot `ms doc` prints (`src/tooling/guide.c` reads `src/stdlib/*.ms`), so signatures, bounds, fields, cases, and operations have one authority. Integration tests compare native conventions against it.

Generated references live in `.artifacts/docs/documentation/standard-library/reference/` and are mounted by Hugo. `website/static/stdlib.md` and `stdlib.json` (versioned, sorted schema) are generated and ignored by Git; `website/static/llms.txt` points to the plain-text API. Change source or generators, then run `make docs` and the book checks; never hand-edit generated output.
