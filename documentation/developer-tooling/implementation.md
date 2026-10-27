+++
title = "Commands and editor setup"
weight = 1
+++

# Commands and editor setup

Use an `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), or build the Rust `ms` in a source checkout (see the [Rust toolchain guide](../contributing/rust-toolchain.md)). Formatting, lint and LSP run directly from `ms`. Native builds and profiling need the pinned linking tools, downloaded and cached on first use; see [how it works](how-it-works.md). There is no `ms debug` or `ms dap`; see [profiling and native debugging](debugging/debugger-integration.md).

```sh
ms lint source.ms --json
ms lint ms.toml --json
ms fmt source.ms --check
ms fmt ms.toml --check
ms fmt source.ms --drop-labels
ms check source.ms --fix
ms verify ms.toml --json
ms lsp
ms search_symbol read file lines
ms search_symbol parse_config
ms search_symbol json
ms profile ms.toml --out-dir capture --top 10 -- arg1
```

- Bare `ms` prints help. `ms version` and `ms --version` print the compiler version.
- Long options take `--output path` or `--output=path`; only the first `=` splits, so `--output=api=v1.md` writes `api=v1.md`. Required values cannot be empty.
- Arguments after `--` are forwarded to the application unchanged.
- Commands taking one source input also accept a project directory with `ms.toml`. Native commands select one application entrypoint.
- `ms check <targets> --fix` and `ms lint <targets> --fix` apply available machine-applicable diagnostic fixes in place, then report what remains. They skip overlapping edits and cannot be combined with `--watch`. See the [diagnostic fix contract](source/diagnostics.md#json-diagnostics) for the supported repairs and JSON fields.

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
ms emit ms.toml -o main.mir
ms diagram ms.toml
ms diagram ms.toml --format mermaid -o calls.mmd
```

These need no linker. `emit` checks and lowers the program, then prints MIR; it does not emit an executable. `inspect` keeps symbols, local names, call sites, source hashes, statement spans, and conservative effects. `diagram` renders the static call graph (not an execution trace): `--format ascii` (default) or `--format mermaid`. Review and diagram describe project declarations; standard-library calls remain boundary leaves and imports remain visible dependencies.

```sh
ms diagram ms.toml --view effects --entity save
ms diagram ms.toml --view errors
ms diagram ms.toml --view tasks --entity load
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
| `tasks` | `flow` pruned to `with` scopes that start tasks: each `TaskGroup.spawn` with the calls its work makes (needs `--entity`) |

- `--entity name`, `file::name`, or a full entity ID roots the tree at one declaration (a project-relative path for `modules`). A missing or ambiguous name fails. Without it, roots are entities nothing relevant calls, plus roots for otherwise unreachable recursive groups. Tests are entry points too.
- `--depth n` bounds expansion (default 3; 1 for `flow`, `scope` and `tasks`). Repeats print `(cycle)`. A view stops at 200 nodes and counts the rest.
- `--diff <file|->` reads a unified diff like `ms review` and marks changed entities with `<- TIER #n` or `<- INTERNAL`, and changed flow lines with `<- changed`. It needs `--view` or `--entity`.
- `--json` emits a versioned document with `view`, `entity`, and `tree` (defaults to the `calls` view). Each tree node has `label`, `kind`, `reference` (a stable entity ID or external call target when available), `file`, `line`, `omitted`, and `children`. Source positions are one-based; line zero means no precise source position. The root's `omitted` counts direct nodes skipped by the output cap. Use `--format mermaid` to render a view for people; `--json` and `--format` cannot be combined.

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
- `--explain <n|id>` (with `--diff`) prints one finding: id, tier, location, score terms, evidence, direct callers, and the diagram command for its flow. `n` is the number under LOOK HERE FIRST; a full id or unambiguous entity name also works. Removed entities and declarations without a callable body have no current flow.
- `--format ascii|markdown` picks the rendering. Text tables show five rows per section unless `--all`; `--json` includes every row and finding. Report format 2 includes `base_checked` (`null` for a project map) and a `number` on each finding (`null` for INTERNAL).
- `--explain <n|id> --json` emits `finding`, structured `callers`, and a `diagram` request with `view` and `entity`, or `null` when no current flow exists. Pass that entity ID directly to `ms diagram --entity`.
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

The report compares tracked static properties; it does not run tests. An INTERNAL body edit can still change runtime behavior. “No tracked semantic changes” means the comparison found no changes to those properties.

For an agent, follow a finding's stable ID through the same workflow:

```sh
ms review ms.toml --diff change.patch --json
ms review ms.toml --diff change.patch --explain 1 --json
ms diagram ms.toml --view flow --entity 'src/main.ms#fn#save' --diff change.patch --json
```

Replace the example ID with `diagram.entity` from the explanation. The diff must be available again for each command; save a piped diff to a file when following up.

## Commands for agents

Two small commands answer what the compiler commands do not and print only what is needed to act.

| Command | Behavior |
| --- | --- |
| `ms search_symbol [<name or words>... \| <path>]` | Fuzzy, case-insensitive lookup over project and standard-library symbols (`--limit n`, default 5, max 10; `--json`). Project matches print `file:line:column`, type, description, and up to five uses; standard matches print signature and path. A lone module or declaration path (`json`, `prelude.List`, `prelude.List.sorted`) prints that page, capped near 3.5 KB; no argument lists modules |
| `ms guide` | The language cheat sheet with a checked example program, then common mistakes beside their fixes (`crates/ms-tooling/data/mistakes.txt`, verified against the compiler by `guide_pages`) |

Pair them with `ms check`, `ms fmt --check`, `ms lint`, and `ms test`, which print compact diagnostics (`--json` for complete documents).

## Selecting independent analysis inputs

`check` and `lint` accept multiple `.ms` files, directories, and `ms.toml` projects. `ms check src utilities.ms --json` checks each input independently; declarations are not combined and no `main` or test runs. Native commands take one entrypoint.

- A directory with `ms.toml` selects that project.
- A directory without one recursively selects `.ms` files, skipping hidden, `vendor`, and `node_modules` directories, directory symlinks, and nested projects. Select nested projects explicitly; explicitly selecting an excluded path is allowed. File symlinks must stay inside the directory.
- Files keep their ordinary import roots. Select `ms.toml` to get project aliases and project-wide checking.
- Use `--` before filenames beginning with `-`. `fmt` keeps its own [directory and manifest discovery](source/formatting.md).

Targets, imported diagnostics, and documented modules are deduplicated and ordered by displayed path and position. Paths inside the invocation directory are relative; others are canonical absolute paths.

- `check` and `lint` continue after an error and return 1 for any failed selection, source error, or finding. Their `format: 1` JSON collects all diagnostics. Empty selections succeed with empty arrays. Usage errors return 2.

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

A nonzero application exit keeps its status with `completed: True` and `reason: "program_exit"`. A signal-terminated process has `completed: False` and `reason: "interrupted"`. Arguments after `--` pass unchanged, and profiles still require a new directory.

## Machine-readable checks and tests

`ms fmt <targets> --check --json`, `ms test <input> --json`, and `ms run <input> --json` write one `format: 1` document to stdout. Usage errors return 2 on stderr with no JSON. `fmt --json` requires `--check`; `test --json --watch` is rejected.

`ms run --json` captures the program's output and reports `exit_code`, `stdout`, `stderr`, and `diagnostics`; compile errors return `reason: "compile_error"` with diagnostics. A program that ends in a runtime fault (exit 67) adds a `fault` object, and `ms test --json` adds the same object to a test that faulted: `kind` (`division_by_zero`, `overflow`, `index_out_of_range`, `stack_overflow`, `deadlock`, `assertion`, `incomplete_cleanup`, or `fault`; an absent `Map` key reports `fault` with `map key not found: <key>`), `message` (which carries the offending values), `position` and `trace` (`function`, `file`, `line`, innermost first, `repeated` when frames collapsed), `trace_truncated`, `cleanups_ran` (the runtime runs every cleanup before it reports), `cleanup_faults`, and `exit_code`. `ms run --json` returns the program's own status.

`ms verify [target] [--json] [--no-test]` runs `check`, `fmt --check`, `lint`, and `test` on one target (default `ms.toml`) and exits 1 when any step fails.

- `--json` writes `target`, `ok`, and a `steps` array in that order. Each step has `name`, `status` (`passed`, `failed`, `skipped`), `exit_code`, `duration_ns`, and `result`, the command's own `--json` document unchanged. A step that cannot produce one carries `error`; a skipped step carries `reason`.
- `lint` and `test` are skipped when `check` fails; `fmt` always runs; `--no-test` skips the native test build.
- Without `--json`, each failed step prints its first eight findings to stderr.

`ms inspect`, `diagram`, and `review` accept `--json` for check failures: unchecked source writes the `check --json` `diagnostics` document and exits 1. Successful diagram and review JSON use the schemas described above.

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

- Test `status` is `passed`, `failed`, or `skipped`. Listing sets `listed: True` and leaves selected tests `not_run`; fail-fast leaves the rest `not_run`. Optional `repeat` and `shuffle_seed` describe order.
- If the process stops early, the active test is `incomplete` and later ones are `not_run`.
- Outcomes come from a separate result channel, so test output that looks like RUN/PASS/FAIL creates none. Stderr never enters the JSON.
- No test blocks: exit 0, `reason: "no_tests"`. Unmatched filter: exit 1, `reason: "no_match"`. Test failures exit 1; abrupt native exits keep their status with `completed: False`. `MST001` marks non-source execution, build, or report failures.

## Editor features

The language server provides incremental sync with validated UTF-16 ranges, diagnostics and lint codes, document and workspace symbols, semantic tokens, folding, inferred-local type hints, hover, definition and type-definition navigation, highlights, references, signature help, formatting, import organization, code actions, and rename.

- Completion follows the checker's lexical scope and member rules: visible parameters and locals, generic-bound operations, record fields, collection and service methods, variant cases, named arguments, snippets (if the client supports them), standard and project auto-imports, and import paths. Used arguments, inaccessible opaque fields, and sibling-scope locals are excluded. An accepted auto-import adds an ordinary import.
- Completion keeps working while code is incomplete; checking, formatting, and builds never accept repaired source.
- References and rename cover declarations, uses, assignments, type annotations, imports, parameter labels, record fields and constructors, and interface operations, including unopened modules. Rename checks the proposed snapshot, rejects identifiers that could capture, and cannot rename external declarations or malformed source.
- Standard-library definitions open read-only in VS Code with hover and navigation.
- VS Code hides inline type hints by default; hover still shows types. Set `editor.inlayHints.enabled` to `on` or `offUnlessPressed` under `[manuscript]` to show hints.

## Linting and formatting

`lint` returns 1 for findings and 0 for clean source. Run `ms check` for correctness errors.

| Code | Finding |
| --- | --- |
| MSL001 | Trailing whitespace |
| MSL002 | Missing final newline |
| MSL102 | Unused import |
| MSL103 | Unreachable statement |
| MSL106 | Capitalized match payload name that creates a fresh binding instead of matching a case. Use a helper or rename. See [payload patterns](../core-language/control-flow/pattern-matching.md#payload-patterns) |
| MSL107 | `match` nested inside another `match`, including inline callbacks. Use an early-exit binding, `try`, or a helper. See [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat) |
| MSL108 | `match` on an Optional with only `some` and `none` arms; use `if let` or an Optional method |
| MSL110 | `Optional.get()` without a default, which faults when the value is absent; use `if let`, `get(default)`, or `get_or_else`. See [Optionals](../core-language/types/optionals.md) |
| MSL111 | `while True` loop in a module that imports `@std/tasks.ms` whose body neither waits nor exits; other tasks cannot run and cancellation or a timeout cannot stop it. See [loops](../core-language/control-flow/loops.md#cancellation) |
| MSL112 | A function that calls itself on every path: no `return`, `try`, or fault leaves it before the recursive call, so it cannot finish. Add a base case. Only direct self-calls of module-level functions are found |

Implicit imports (such as `List` for list literals) count as uses. Unused-import and whitespace fixes are editor actions; initializers with possible effects are never silently removed.

`fmt` takes files, directories, and manifests (see [formatting](source/formatting.md)).

- `--check` reports every unformatted file and fails if any needs formatting or cannot be processed.
- `--drop-labels` removes redundant labels (`key: key` where the parameter binds by position anyway) using the checked program. It leaves the file untouched and reports the first diagnostic if it does not check; with `--check` it reports files that would change.
- It preserves comments and token spellings, validates input and output, and writes atomically. Import sorting keeps comment and blank-line group boundaries.

Format code as paragraphs: keep related steps together and put space between new sections. Blank lines come only from these structural rules; authored ones are discarded. Rules also apply inside anonymous functions.

- Separate top-level declarations from each other and from imports, and implementation methods from each other. Interface signatures, record fields, and alternative cases stay compact.
- Separate substantial conditionals, loops, resource scopes, and matches from neighbors. A single-step branch or loop without `else` stays with adjacent work.
- Keep local bindings with the actions, checks, or simple return that follow them. Start a new paragraph when another binding follows completed work.
- Start a paragraph before a leading comment between statements; keep the comment attached to the code it introduces.
- Give multi-statement callback definitions and calls their own paragraphs, like other substantial blocks. A short callback stays with adjacent work.
- A guard (`if` without `else` and one `return`, `break`, or `continue`) stays with preceding setup and other guards, then a blank line follows.
- Keep each `if`/`elif`/`else` family and all match arms together. Inserted breaks go before leading comments.

Expression layout uses a soft limit of 88 columns:

- Calls and signatures stay on one line when they fit (including the return type, excluding callback bodies). An anonymous function with a multi-statement suite always expands its call.
- A callback containing one explicit `return` joins its header when it has no nested suites or intervening comments, so short calls such as `queue.enqueue(lambda: return 7)` stay compact. A bare call body remains indented because making it inline would implicitly return its value.
- Lists, grouped imports, and maps stay compact when they fit. Wrapped lists pack simple elements into rows; nested groups, expressions, and commented items get their own lines.
- When a group expands, each item goes on its own line, indented four spaces, closing delimiter aligned with the opening line. An authored multiline group collapses if it fits and has no comment or suite.
- Long conditions break at the lowest-precedence logical operator, keeping comparison operands together. Long arithmetic and member chains gain continuation lines, with grouping parentheses where needed.
- Inside calls, collections, and parameter lists, use the existing delimiters for continuation; do not add grouping parentheses just to wrap an item.
- Comments force expansion and stay with their opener, argument, or item.
- String literals, interpolations, and comment text are never split or rewritten.

## Debugging and profiling

The Rust `ms` has no debugger. Native builds keep frame pointers and DWARF line tables, so faults report source frames and external tools such as `perf` can attribute samples; see [profiling and native debugging](debugging/debugger-integration.md).

`ms profile module-or-project --out-dir new-directory` builds the application, runs it with the sampling profiler, and writes `program`, `profile.folded`, `profile.pb` (pprof), `top.txt`, and `manifest.json`. Existing directories are rejected. Profiling adds overhead, so measure an unprofiled executable when comparing speed.

```sh
ms profile main.ms --out-dir samples --top 10
```
