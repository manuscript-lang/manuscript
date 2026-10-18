+++
title = "Commands and editor setup"
weight = 1
+++

# Commands and editor setup

Use a self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), or run `make build` in a source checkout. Compilation, formatting, lint, LSP, profiling, and native debugging (embedded Delve) need no separate Go or `dlv`.

macOS still needs Apple's `debugserver` from the Xcode command line tools; see [debugger integration](debugging/debugger-integration.md).

```sh
ms lint source.ms --json
ms lint ms.toml --json
ms fmt source.ms --check
ms fmt ms.toml --check
ms fmt source.ms --drop-labels
ms verify ms.toml --json
ms lsp
ms search_symbol read file lines
ms search_symbol parse_config
ms search_symbol json
ms debug source.ms -- arg1
ms debug source.ms --break source.ms:7 --json
ms debug ms.toml --script commands.txt
ms run source.ms --cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out -- arg1
ms pprof -tags cpu.pprof
ms pprof -http=127.0.0.1:8080 cpu.pprof
ms trace trace.out
```

- Bare `ms` prints help. `ms version` and `ms --version` print the compiler version.
- Long options take `--output path` or `--output=path`; only the first `=` splits, so `--output=api=v1.md` writes `api=v1.md`. Required values cannot be empty.
- Arguments after `--` and options for `ms pprof` and `ms trace` are forwarded unchanged.
- Commands taking one source input also accept a project directory with `ms.toml`. Native commands select one application entrypoint.

## Rebuild on save

```sh
ms run ms.toml --watch -- arg1
ms test test.ms --watch
```

- `run` and `test` rebuild after each saved change to the manifest or a loaded local module, then restart. The old program gets an interrupt and five seconds for cleanup, and is stopped only after its replacement builds. A failed edit prints diagnostics and keeps watching.
- `ms check <targets> --watch` and `ms lint <targets> --watch` rerun after each saved change and keep watching through errors and findings. `--json` cannot be combined with `--watch`.
- Interrupting `ms` exits with status 130. See [cache boundaries](builds/incremental-compilation.md) for what a rebuild still compiles.

Project lint covers every reachable local module. [Library projects](builds/project-configuration.md#library-projects-and-copied-dependencies) include all source modules and discovered tests.

## Source inspection

```sh
ms check ms.toml --json
ms inspect ms.toml -o inspection.json
ms diagram ms.toml
ms diagram ms.toml --format mermaid -o calls.mmd
```

These need no Go installation or native toolchain. `inspect` keeps symbols, local names, call sites, source hashes, statement spans, and conservative effects. `diagram` renders the static call graph (not an execution trace): `--format ascii` (default) or `--format mermaid`.

```sh
ms diagram ms.toml --view effects --entity save
ms diagram ms.toml --view errors
ms diagram ms.toml --view modules
ms diagram ms.toml --view flow --entity main --depth 2
ms diagram ms.toml --view scope --entity save
ms diagram ms.toml --view flow --entity save --diff change.patch
```

| `--view` | Shows |
| --- | --- |
| `calls` | Who is called; native boundaries are leaves |
| `effects` | Callees that carry an effect, down to the native operation |
| `errors` | Functions with a `Result` error type or `try` sites |
| `modules` | Imports per module |
| `flow` | One function's ordered steps: calls, `try`, branches, loops, `match` arms, `with` scopes, exits (needs `--entity`) |
| `scope` | `flow` pruned to `with` scopes and the exits inside them (needs `--entity`) |

- `--entity name` or `file::name` roots the tree at one declaration (a project-relative path for `modules`). A missing or ambiguous name fails. Without it, roots are entities nothing relevant calls.
- `--depth n` bounds expansion (default 3; 1 for `flow` and `scope`). Repeats print `(cycle)`. A view stops at 200 nodes and counts the rest.
- `--diff <file|->` reads a unified diff like `ms review` and marks changed entities with `<- TIER #n` or `<- INTERNAL`, and changed flow lines with `<- changed`. It needs `--view` or `--entity`.

## Review report

```sh
ms review ms.toml
git diff --no-renames main... | ms review ms.toml --diff -
ms review ms.toml --diff change.patch --format markdown
ms review ms.toml --diff change.patch --explain 1
```

`ms review` prints where a reader should look. Every line is a fixed template filled with facts from the checked program, so equal inputs print equal bytes (no timestamps, absolute paths, or width dependence). An empty section prints `none`.

- Without `--diff`: the project map of public surface, entry points with effects, error types in signatures, `with` scopes, and imports.
- With `--diff`: compares the checked program before and after. Pass a unified diff from a file or stdin (`git diff --no-renames` or `diff -u`); `ms` does not run git. The working tree must be the diff's after state. A diff that does not match is rejected with status 2. Renames are unsupported.
- `--explain <n|id>` (with `--diff`) prints one finding: id, tier, location, score terms, evidence, direct callers, and the diagram command for its flow. `n` is the number under LOOK HERE FIRST; an id or entity name also works.
- `--format ascii|markdown|json` picks the rendering. Tables show five rows per section unless `--all`.
- If the before state does not check, the report says so and lists only touched entities. If the current tree fails checking, it prints diagnostics and exits 1.

Entities match by file, kind, and name, so formatting and in-file moves are not changes. Tiers:

| Tier | Meaning |
| --- | --- |
| `CONTRACT` | Exported signature or visibility change, exported entity added or removed |
| `EFFECT+` | New conservative effect, with the call path to where it enters |
| `ERROR` | Different `Result` error type or number of `try` sites |
| `RESOURCE` | Different number of `with` scopes |
| `INTERNAL` | Body changed without affecting any tier |

Reach is the number of entities that transitively call the changed one; the score is the sum of the listed terms. `unknown` effects appear for indirect calls and most native operations, so only newly introduced effects rank.

## Commands for agents

Two small commands answer what the compiler commands do not and print only what is needed to act.

| Command | Behavior |
| --- | --- |
| `ms search_symbol [<name or words>... \| <path>]` | Fuzzy, case-insensitive lookup over project and standard-library symbols (`--limit n`, default 5, max 10; `--json`). Project matches print `file:line:column`, type, description, and up to five uses; standard matches print signature and path. A lone module or declaration path (`json`, `prelude.List`, `prelude.List.sorted`) prints that page, capped near 3.5 KB; no argument lists modules |
| `ms guide` | The language cheat sheet (under 2.5 KB) with a checked example program |

Pair them with `ms check`, `ms fmt --check`, `ms lint`, and `ms test`, which print compact diagnostics (`--json` for complete documents).

## Selecting independent analysis inputs

`check` and `lint` accept multiple `.ms` files, directories, and `ms.toml` projects. `ms check src utilities.ms --json` checks each input independently; declarations are not combined and no `main` or test runs. Native commands take one entrypoint.

- A directory with `ms.toml` selects that project.
- A directory without one recursively selects `.ms` files, skipping hidden, `vendor`, and `node_modules` directories, directory symlinks, and nested projects. Select nested projects explicitly; explicitly selecting an excluded path is allowed. File symlinks must stay inside the directory.
- Files keep their ordinary import roots. Select `ms.toml` to get project aliases and project-wide checking.
- Use `--` before filenames beginning with `-`. `fmt` keeps its own [directory and manifest discovery](source/formatting.md).

Targets, imported diagnostics, and documented modules are deduplicated and ordered by displayed path and position. Paths inside the invocation directory are relative; others are canonical absolute paths.

- `check` and `lint` continue after an error and return 1 for any failed selection, source error, or finding. Their `format: 1` JSON collects all diagnostics. Empty selections succeed with empty arrays. Usage errors return 2.
- `doc` checks every input before writing the combined reference. On any error it returns 1, reports on stderr, and leaves stdout and an existing output file untouched. `--stdlib` takes no inputs. If one module has conflicting API snapshots across input graphs, `doc` rejects it; select one input or a manifest defining one graph.

## Machine-readable native results

`ms build <input> --json` and `ms profile <input> --json` write one `format: 1` document to stdout. Usage errors return 2 on stderr with no JSON. Stderr stays stderr; profile captures application stdout untruncated.

| Field | Meaning |
| --- | --- |
| `command`, `build_type` | `build` or `profile`, and the native build level |
| `source_root`, `output` | Source root and absolute executable or bundle destination |
| `completed`, `exit_code` | Build success or normal process completion, and CLI status |
| `reason` | Optional `compile_error`, `build_error`, `artifact_error`, `execution_error`, `output_error`, `program_exit`, or `interrupted` |
| `artifacts` | Planned artifacts in stable order, each with `kind`, absolute `path`, and `state` |
| `stdout`, `stdout_base64` | Captured application text, or base64 for invalid UTF-8 (then `stdout` is empty) |
| `diagnostics` | Source diagnostics or `MSN001` operational errors; an array even when empty |

Artifact `state` values:

| State | Meaning |
| --- | --- |
| `verified` | Builder or reference step succeeded |
| `written` | New or changed file |
| `preserved` | Unchanged existing file |
| `missing` | Absent file |
| `unavailable` | Path cannot be read as a regular file |

A failed check preserves prior files and creates no capture directory. Only a completed build establishes a valid executable and metadata pair; a partial result identifies any partial output.

Profile keeps CPU and heap by default; `--trace` adds the trace.

A nonzero application exit keeps its status with `completed: true` and `reason: "program_exit"`. A signal-terminated process has `completed: false` and `reason: "interrupted"`. Arguments after `--` pass unchanged, and profiles still require a new directory.

## Machine-readable checks and tests

`ms fmt <targets> --check --json` and `ms test <input> --json` write one `format: 1` document to stdout. Usage errors return 2 on stderr with no JSON. `fmt --json` requires `--check`; `test --json --watch` is rejected.

`ms verify [target] [--json] [--no-test]` runs `check`, `fmt --check`, `lint`, and `test` on one target (default `ms.toml`) and exits 1 when any step fails.

- `--json` writes `target`, `ok`, and a `steps` array in that order. Each step has `name`, `status` (`passed`, `failed`, `skipped`), `exit_code`, `duration_ns`, and `result`, the command's own `--json` document unchanged. A step that cannot produce one carries `error`; a skipped step carries `reason`.
- `lint` and `test` are skipped when `check` fails; `fmt` always runs; `--no-test` skips the native test build.
- Without `--json`, each failed step prints its first eight findings to stderr.

`ms inspect`, `diagram`, and `emit` accept `--json` for failures only: unchecked source writes the `check --json` `diagnostics` document and exits 1.

Formatting results contain `files` and `diagnostics`, both arrays even when empty. Each file has `path` and `status`: `clean`, `needs_formatting`, or `error`. Files are deduplicated and ordered by displayed path. Drift is `MSF001`; selection and I/O errors are `MSF002`; parse and manifest diagnostics keep their codes. The command writes no source, returns 1 on any drift or error, and still reports other files. An empty selection succeeds.

Test results:

| Field | Meaning |
| --- | --- |
| `source_root` | Root for module-relative diagnostic paths and test names |
| `tests` | Planned tests in execution order, each with `index`, `name`, `status`, `duration_ns`, and optional `failure` text with its first source `position` |
| `summary` | `available` declaration count; `selected`, `passed`, `failed`, `skipped`, `not_run` counts; total `duration_ns` |
| `completed` | Whether the runner finished its plan (also true for listing or fail-fast) |
| `exit_code` | CLI exit status |
| `stdout` | Complete captured native stdout |
| `stdout_base64` | Replaces `stdout` (then empty) when bytes are not valid UTF-8 |
| `diagnostics` | Compile diagnostics, or execution, build, or report errors; empty on ordinary runs |
| `fixture_errors` | Optional file-level lifecycle failures with `file`, `phase`, `failure`, optional `position` |
| `reason` | Optional `fixture_error`, `fixture_abandoned`, `cancelled`, `listed`, `fail_fast`, `no_tests`, `no_match`, `compile_error`, `build_error`, `execution_error`, or `argument_error` |

- Test `status` is `passed`, `failed`, or `skipped`. Listing sets `listed: true` and leaves selected tests `not_run`; fail-fast leaves the rest `not_run`. Optional `repeat` and `shuffle_seed` describe order.
- If the process stops early, the active test is `incomplete` and later ones are `not_run`.
- Outcomes come from a separate result channel, so test output that looks like RUN/PASS/FAIL creates none. Stderr never enters the JSON.
- No test blocks: exit 0, `reason: "no_tests"`. Unmatched filter: exit 1, `reason: "no_match"`. Test failures exit 1; abrupt native exits keep their status with `completed: false`. `MST001` marks non-source execution, build, or report failures.

`ms emit ms.toml -o main.go` writes generated Go with the runtime included. Compiling it directly needs the repository's pinned `go.mod`, `go.sum`, `vendor/` tree, and `internal/hostos/`; from a checkout use `toolchain/go/bin/go build -mod=vendor main.go`. `build`, `run`, and `test` supply these themselves. See [how it works](how-it-works.md).

## Editor features

The language server provides incremental sync with validated UTF-16 ranges, diagnostics and lint codes, document and workspace symbols, semantic tokens, folding, inferred-local type hints, hover, definition and type-definition navigation, highlights, references, signature help, formatting, import organization, code actions, and rename.

- Completion follows the checker's lexical scope and member rules: visible parameters and locals, generic-bound operations, record fields, collection and service methods, variant cases, named arguments, snippets (if the client supports them), standard and project auto-imports, and import paths. Used arguments, inaccessible opaque fields, and sibling-scope locals are excluded. An accepted auto-import adds an ordinary import.
- Incomplete member accesses and calls are analyzed on a private snapshot with declaration recovery. Recovery is editor-only; strict checking, formatting, and builds never accept repaired source. A parse error elsewhere does not erase completion or outlining.
- References and rename cover declarations, uses, assignments, type annotations, imports, parameter labels, record fields and constructors, and interface operations, including unopened modules. Rename checks the proposed snapshot, rejects identifiers that could capture, and cannot rename external declarations or malformed source.
- Standard-library definitions open read-only in VS Code with hover and navigation.
- Open documents share recovering project analysis, occurrence indexes and lint findings within the current source generation. Any source or manifest change discards that generation; repaired completion and strict workspace checks remain separate. Consecutive already-queued edits apply in order and may publish only the latest diagnostics before the next request or lifecycle event.
- Transport limits: 16 MiB frames, 8 KiB headers. Invalid JSON or parameters get protocol errors without ending the session. Canceled requests return `RequestCancelled`.
- Cancellation skips queued requests and stops workspace work between files and checking phases. A compiler check or occurrence-index construction already in progress finishes before cancellation is observed.

## Linting and formatting

`lint` returns 1 for findings and 0 for clean source. Run `ms check` for correctness errors.

| Code | Finding |
| --- | --- |
| MSL001 | Trailing whitespace |
| MSL002 | Missing final newline |
| MSL101 | Unread local or match payload binding (a read inside `total = total + 2` does not count; use `_` to ignore a payload) |
| MSL102 | Unused import |
| MSL103 | Unreachable statement |
| MSL104 | Discarded `Result`: handle with `match`, propagate with `try`, or bind `let _ignored = operation()`. See [Result handling](../core-language/errors/results.md) |
| MSL105 | Captured mutation in a known concurrent callback; advisory, not a race-freedom proof. Use one `Synchronized` wrapper |
| MSL106 | Capitalized match payload name that creates a fresh binding instead of matching a case. Use a helper or rename. See [payload patterns](../core-language/control-flow/pattern-matching.md#payload-patterns) |
| MSL107 | `match` nested inside another `match`, including inline callbacks. Use an early-exit binding, `try`, or a helper. See [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat) |
| MSL108 | `match` on an Optional with only `some` and `none` arms; use `if let` or an Optional method |

Implicit imports (such as `List` for list literals) count as uses. Unused-import and whitespace fixes are editor actions; initializers with possible effects are never silently removed.

`String.replace_first` still accepts a cap greater than one, so renaming every `String.replace` call would conceal that behavior; both names keep their signatures.

`fmt` takes files, directories, and manifests (see [formatting](source/formatting.md)).

- `--check` reports every unformatted file and fails if any needs formatting or cannot be processed.
- `--drop-labels` removes redundant labels (`key: key` where the parameter binds by position anyway) using the checked program. It leaves the file untouched and reports the first diagnostic if it does not check; with `--check` it reports files that would change.
- It preserves comments and token spellings, validates input and output, and writes atomically. Import sorting keeps comment and blank-line group boundaries.

Blank lines come only from these structural rules; authored ones are discarded. Rules also apply inside anonymous functions.

- Separate top-level declarations from each other and from imports, and implementation methods from each other. Interface signatures, record fields, and alternative cases stay compact.
- Separate substantial conditionals, loops, resource scopes, and matches from neighbors. A single-step branch or loop without `else` stays with adjacent work.
- A guard (`if` without `else` and one `return`, `break`, or `continue`) stays with preceding setup and other guards, then a blank line follows.
- Keep each `if`/`else if`/`else` family and all match arms together. Inserted breaks go before leading comments.

Expression layout uses a soft limit of 88 columns:

- Calls and signatures stay on one line when they fit (including the return type, excluding callback bodies). An anonymous function with a multi-statement suite always expands its call.
- Lists, grouped imports, and maps stay compact when they fit. Wrapped lists pack simple elements into rows; nested groups, expressions, and commented items get their own lines.
- When a group expands, each item goes on its own line, indented four spaces, closing delimiter aligned with the opening line. An authored multiline group collapses if it fits and has no comment or suite.
- Long conditions break at the lowest-precedence logical operator, keeping comparison operands together. Long arithmetic and member chains gain continuation lines, with grouping parentheses where needed.
- Comments force expansion and stay with their opener, argument, or item.
- String literals, interpolations, and comment text are never split or rewritten.

## Debugging and profiling

`ms debug` opens Delve's terminal UI. `ms debug --break <location>` and `ms debug --script <file>` are non-interactive; see [scripted debugging](debugging/debugger-integration.md#scripted-debugging-for-agents).

- Profiling is explicit and local: CPU and heap use pprof, traces use Go tracing. New files are created exclusively with mode 0600 and existing files are never overwritten. Setup or heap-write errors exit 70. One capture runs per process.
- Source entry boundaries add `ms.source` CPU labels and, when tracing, `source:<position>` regions. Nested calls inherit the label and appear in sampled stacks through native source mappings. Each task-group or scheduled operation starts a fresh boundary; joining and cleanup have named trace regions. Heap-only capture adds no instrumentation.
- Profiling changes timing and allocation: CPU capture waits for samples to flush, heap capture forces a garbage collection, and tracing can add time and disk use. Use optimized builds, and measure an unprofiled executable when comparing speed.
- The VS Code debugger shows native runtime frames as subdued entries (scripted `ms debug` omits them), and complex watch expressions keep native Go syntax.

`ms profile module-or-project --out-dir new-directory` captures `cpu.pprof` and `heap.pprof` and keeps the optimized executable, build and source metadata, static inspection, and a bundle manifest for symbolization. `-o` and `--output` alias `--out-dir`. `--trace` adds `trace.out` (off by default). Existing directories are rejected. For individual paths use `ms run … --cpu-profile path --heap-profile path --trace path`.

```sh
ms profile main.ms --out-dir samples
ms profile main.ms --out-dir traced-samples --trace
ms pprof -top samples/cpu.pprof
ms trace -http=127.0.0.1:8080 traced-samples/trace.out
```
