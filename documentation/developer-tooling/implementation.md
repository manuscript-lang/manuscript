+++
title = "Commands and editor setup"
weight = 1
+++

# Commands and editor setup

Use a self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), or run `make build` in a source checkout to prepare the pinned Go SDK automatically. Compilation, formatting, lint, LSP, and profiling need no separate Go installation. Native debugging uses Delve embedded in `ms`, with no separate `dlv` installation. macOS still requires Apple’s `debugserver` from Xcode command line tools; see [debugger integration](debugging/debugger-integration.md). The VS Code extension provides its own Manuscript DAP layer over Delve.

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

Bare `ms` prints help and exits successfully. Value-taking long options accept
both `--output path` and `--output=path`; only the first `=` separates the flag
from its value, so `--output=api=v1.md` writes `api=v1.md`. The same rule applies
to build types, test timeouts/filters, and profile paths. Required values cannot
be empty. Arguments after `--` and options for `ms pprof`/`ms trace` are forwarded
to their existing consumers.

`ms version` and `ms --version` print the same compiler version. Both reject
extra arguments with usage status 2; `ms version --help` shows command help.

Commands that take one source input also accept a project directory containing
`ms.toml`; native commands select one application entrypoint.
`fmt` selects multiple files or recursively discovers directories as described
in [formatting](source/formatting.md).

## Rebuild on save

```sh
ms run ms.toml --watch -- arg1
ms test test.ms --watch
```

`--watch` keeps one `ms` process alive, rebuilds after each saved change to the manifest or any loaded local module, and restarts the program. The running program is interrupted, given five seconds to finish cleanup, and then killed, but only after its replacement builds; a failed edit prints diagnostics and keeps watching. Each restart reports the time from the save. Interrupting `ms` interrupts the program and exits with status 130. See [cache boundaries](builds/incremental-compilation.md) for what a rebuild still compiles and links.

`ms check <targets> --watch` and `ms lint <targets> --watch` rerun the analysis after each saved change to a target, its manifest, or any local module it loaded, printing the usual diagnostics each time. Errors and lint findings keep watching; interrupting exits with status 130. `--json` cannot be combined with `--watch`. Files added to a watched directory are picked up on the next change to a watched file.

Project lint checks hygiene in every reachable local module and runs semantic rules on the checked program. [Library projects](builds/project-configuration.md#library-projects-and-copied-dependencies) include all source modules and discovered tests. `--json` reports stable rule codes and module-relative positions.

## Source inspection

```sh
ms check ms.toml --json
ms inspect ms.toml -o inspection.json
ms diagram ms.toml
ms diagram ms.toml --format mermaid -o calls.mmd
```

These commands use source checking without a Go installation or native toolchain extraction. `inspect` retains symbols, local names, call sites, source hashes, statement spans, and conservative effects. `diagram` renders their static call graph; it is not an execution trace. `--format ascii` (the default) prints a plain-text outline in a fixed order: entities by identity, each followed by its distinct callees with a repeat count. `--format mermaid` prints a flowchart for rendering.

## Review report

```sh
ms review ms.toml
git diff --no-renames main... | ms review ms.toml --diff -
ms review ms.toml --diff change.patch --format markdown
```

`ms review` prints a report of where a reader should look. Every line is a fixed template filled with facts from the checked program; no text is generated. Sections always appear in the same order, an empty section prints `none`, and the report ends with a digest of its body, so equal inputs print equal bytes. Output has no timestamps, absolute paths, or terminal-width dependence.

- Without `--diff` the report maps the project: public surface, entry points with their effects, error types in signatures, `with` scopes, and imports.
- With `--diff` it compares the checked program before and after the change. `ms` does not run git: pass a unified diff from a file or standard input (`git diff --no-renames` or `diff -u`). The working tree must be the diff's after state. The before state is rebuilt by reversing the diff over the touched `.ms` files in memory; every context and added line is verified, and a diff that does not match the tree is rejected with status 2. Renames are not supported.
- Entities are matched by file, kind, and name, so formatting and moves within a file are not changes. A change is ranked by tier: `CONTRACT` (exported signature or visibility, added or removed exported entity), `EFFECT+` (a new conservative effect, with the call path to where it enters), `ERROR` (a different `Result` error type or number of `try` sites), and `RESOURCE` (a different number of `with` scopes). Reach is the number of entities that transitively call the changed one. The score is the sum of the listed terms; `INTERNAL` lists entities whose body changed without affecting any tier.
- When the before state does not check, the report says so and lists only entities touched by the diff.
- `--format ascii|markdown|json` selects the rendering of one report. Tables show five rows per section unless `--all` is given. Failed checking of the current tree prints the usual diagnostics and exits 1.

The effect tier inherits the checker's conservatism: `unknown` appears for indirect calls and most native operations, so only a newly introduced effect ranks.

## Commands for agents

Agents with a shell need no protocol server: three small commands answer what the compiler commands do not, and each prints only what is needed to act.

| Command | Behavior |
| --- | --- |
| `ms search_symbol [<name or words>... \| <path>]` | Fuzzy, case-insensitive lookup over project declarations and standard-library symbols (partial names, missing underscores, small typos, plain words; exact names first; `--limit n` default 5, at most 10; `--json`). A project match prints its definition `file:line:column`, type, one-line description, and up to five uses, from the language server's analysis; a standard match prints its signature and a path. A lone module or declaration path (`json`, `prelude.List`, `prelude.List.sorted`) prints that page, each capped near 3.5 KB; no argument lists modules |
| `ms guide` | The language cheat sheet (under 2.5 KB) with a checked example program |

Pair them with `ms check`, `ms fmt --check`, `ms lint`, and `ms test`, which already print compact diagnostics and failures (`--json` for complete documents). The index is built from the checker's definitions, so it does not depend on any exported declaration files. The cheat sheet stays under 2,500 bytes because agents read it every session, and a test checks its complete program.

## Selecting independent analysis inputs

`check` and `lint` accept multiple `.ms` files, directories, and `ms.toml`
projects. For example, `ms check src utilities.ms --json` checks each selected
input independently. It does not combine their declarations or execute their
`main` functions or test blocks. Native commands still take one entrypoint.

A directory containing `ms.toml` selects that project and retains the command's
existing project behavior. A directory without its own manifest recursively
selects `.ms` files, skipping hidden, `vendor`, and `node_modules` directories,
directory symlinks, and nested directories containing `ms.toml`. Select nested
projects explicitly. Selecting an excluded directory or file explicitly is
allowed. Discovered file symlinks must stay inside the selected directory.
Files keep their ordinary import roots; selecting a directory does not grant
parent-directory imports or inherit manifest aliases. Select `ms.toml` to use
project aliases and project-wide checking. These additions do not change fmt's
existing [directory and manifest discovery](source/formatting.md).

Collections deduplicate canonical targets, imported diagnostics, and documented
modules. Targets and diagnostics are ordered by displayed path and source
position; module documentation paths use `/` separators. Paths inside the
invocation directory are relative to it, and outside paths are canonical
absolute paths. The existing single-file/project path spelling is preserved.
Use `--` before literal filenames beginning with `-`.

Check and lint process other independent inputs after an error, returning 1 for
any failed selection, source error, or lint finding. Their existing `format: 1`
JSON documents collect all diagnostics; lint findings retain their existing
shape alongside source diagnostics. Empty standalone selections succeed with
empty arrays. Usage errors return 2 before checking.

Doc checks every input before writing its combined public module reference.
On any error it returns 1, reports diagnostics on stderr, and leaves stdout and
an existing output file untouched. Successful JSON retains `format: 1` and the
`modules` array; an empty selection produces an empty reference. `--stdlib`
continues to require no input targets. If one physical module has different API
snapshots in separate input graphs (for example, different local interface
implementations), doc rejects the conflicting descriptions. Select one input
or a project manifest defining one complete graph instead.

## Machine-readable native results

`ms build <input> --json` and `ms profile <input> --json` emit one `format: 1`
JSON document on stdout. Human output remains the default. Usage errors return
2 on stderr without JSON, matching the other structured commands. Source and
operational failures return a document with their normal status. Stderr remains
stderr; profile captures application stdout without truncation.

| Field | Meaning |
| --- | --- |
| `command`, `build_type` | `build` or `profile`, and the selected native build level |
| `source_root`, `output` | Source root and absolute executable/bundle destination |
| `completed`, `exit_code` | Build success or normal native process completion, and observable CLI status |
| `reason` | Optional `compile_error`, `build_error`, `artifact_error`, `execution_error`, `output_error`, `program_exit`, or `interrupted` |
| `artifacts` | Planned artifacts in stable order, each with `kind`, absolute `path`, and `state` |
| `stdout`, `stdout_base64` | Captured application text, or base64 for invalid UTF-8 (then `stdout` is empty) |
| `diagnostics` | Existing source diagnostic shapes, or `MSN001` operational errors; an array even when empty |

Artifact states are `verified` after a successful builder/reference step,
`written` for a newly created or changed file, `preserved` for an unchanged
existing file, `missing` for an absent file, or `unavailable` when a path cannot
be read as a regular file. This inventory describes partial failures without
claiming that an old output belongs to a failed source check. A failed check
preserves prior files and creates no capture directory. Build publication can
produce an executable before metadata fails; the result identifies that partial
output. Only a completed successful build establishes a valid executable and
metadata pair.

Profile retains CPU/heap by default; `--trace` adds trace to the manifest and
inventory. A normal nonzero application exit retains its status, has
`completed: true` and `reason: "program_exit"`, and does not invent a source
diagnostic. A process terminated by a signal has `completed: false` and
`reason: "interrupted"`; its existing observable status is preserved. Arguments
after `--` are passed unchanged, and profiles still require a new directory.

## Machine-readable checks and tests

`ms fmt <targets> --check --json` and `ms test <input> --json` write one JSON
document to stdout, with `format: 1`. Human output remains the default. Usage
errors return 2 on stderr without a JSON document, as with `check --json`.
`fmt --json` requires `--check`; `test --json --watch` is rejected because a
single result cannot describe an ongoing sequence of runs.

`ms verify [target] [--json] [--no-test]` runs `check`, `fmt --check`, `lint`, and
`test` on one target (default `ms.toml`) and exits 1 when any step fails. With
`--json` it writes one document, `format: 1`, with `target`, `ok`, and a `steps`
array in that order. Each step has `name`, `status` (`passed`, `failed`, or
`skipped`), `exit_code`, `duration_ns`, and `result`, which is that command's own
`--json` document unchanged. A step that cannot produce one carries `error` text
instead, and a skipped step carries `reason`. `lint` and `test` are skipped when
`check` fails; `fmt` always runs; `--no-test` skips the native test build. Without
`--json`, each failed step also prints its first eight findings to stderr.

`ms inspect`, `diagram`, and `emit` accept `--json` for failures only: when the
source does not check, they write the same `format: 1` `diagnostics` document as
`check --json` and exit 1. Successful output is unchanged.

Formatting results contain `files` and `diagnostics`, both arrays even when empty.
Each file has a `path` and a `status`: `clean`, `needs_formatting`, or `error`.
Files are deduplicated by physical identity and ordered by displayed path.
Paths inside the invocation directory are relative to it; paths outside it are
canonical absolute paths. Explicit files, directories, manifests and symlinks
use the same display rule. Formatting drift has code `MSF001`; selection/I/O
errors use `MSF002`. Parse and manifest diagnostics retain their existing codes,
phases, messages and source positions. Diagnostics are ordered by path, source
position, code and message. The command writes no source and returns 1 for any
drift or error; other files still receive results. An empty selection succeeds.

Test results contain these fields:

| Field | Meaning |
| --- | --- |
| `source_root` | Root for module-relative compile diagnostic paths and test names |
| `tests` | Planned tests in execution order; each has an execution `index`, `name`, `status`, `duration_ns`, and optional `failure` text with its first source `position` |
| `summary` | `available` declaration count; `selected`, `passed`, `failed`, `skipped`, and `not_run` execution counts; total `duration_ns` |
| `completed` | Whether the native runner finished its plan (also true for listing or fail-fast) |
| `exit_code` | Observable CLI exit status |
| `stdout` | Complete captured native stdout, including runner and test-written output |
| `stdout_base64` | Present instead of stdout text when bytes are not valid UTF-8; `stdout` is then empty |
| `diagnostics` | Existing compile diagnostics, or execution/build/report errors; an empty array on ordinary runs |
| `fixture_errors` | Optional file-level lifecycle failures with `file`, `phase`, `failure`, and optional source `position` |
| `reason` | Optional `fixture_error`, `fixture_abandoned`, `cancelled`, `listed`, `fail_fast`, `no_tests`, `no_match`, `compile_error`, `build_error`, `execution_error`, or `argument_error` |

Completed tests have status `passed`, `failed`, or `skipped`. Listing sets
`listed: true` and leaves every selected test `not_run`; fail-fast leaves its
remaining executions `not_run`. The optional `repeat` count and `shuffle_seed`
describe execution order. Repeated names have distinct indices and durations.
Per-test durations include cleanup; total duration includes runner overhead. If the process stops early,
the active test is `incomplete`, later planned tests are `not_run`, and completed
outcomes remain available. Failure text retains source frames and timeout details.
The native test executable writes outcomes through a separate result channel;
test-written text resembling RUN/PASS/FAIL lines does not create outcomes.
Native stderr stays on stderr and is never mixed into the JSON document.
The default human transcript and test working directory are unchanged.

No test blocks return 0 with `reason: "no_tests"`. An unmatched filter returns
1 with `reason: "no_match"`, zero selected tests and the available count.
Ordinary test failures retain exit 1; abrupt native exits keep their existing
status and set `completed: false`. Compile failures have no planned tests and
retain source diagnostics in the document. `MST001` identifies non-source
test execution/build/report failures. No test output is truncated.

`ms emit ms.toml -o main.go` writes generated Go with the runtime included. Compiling emitted source directly still requires the repository's pinned `go.mod`, `go.sum`, `vendor/` tree, and `internal/hostos/` platform helpers. From a checkout, use `toolchain/go/bin/go build -mod=vendor main.go`. Ordinary `ms build`, `run`, and `test` supply those inputs themselves. See [pins and native builds](builds/reproducibility.md).

## Editor features

The server supports incremental document synchronization with validated UTF-16 ranges, compiler diagnostics and advisory lint codes, hierarchical document symbols, workspace symbol search, semantic tokens, folding, inferred-local type hints, typed hover, definition/type-definition navigation, highlights, project references, signature help, formatting, import organization, and versioned code actions and rename edits.

Completion is derived from the checker's actual lexical scope and member-resolution rules. It resolves shadowing and offers visible parameters/locals, generic-bound operations, substituted record fields and collection/service methods, variant cases, named call arguments, generic/call snippets, standard and project auto-imports, and import names/paths. Used arguments, inaccessible opaque fields, and locals in sibling scopes are excluded. Snippets are offered only when the client supports them. Accepting an auto-import creates an explicit ordinary import.

Incomplete member accesses and calls are analyzed using a private cursor snapshot. Declaration recovery retains unaffected source with original positions. Recovery is exclusive to editor analysis: strict checking, formatting, and native builds never accept repaired source. A parse error elsewhere does not erase completion or outlining for valid declarations. Analysis skips Go lowering and caches normal document results until source or watched files change. Member completion's local benchmark is included in `completion_test.go`.

References and rename cover declaration names, expression uses, assignments, type annotations, imports, named parameter labels, record fields/constructors, and source interface operations. Project scans include unopened modules. Rename checks the proposed workspace snapshot before returning edits and uses document versions for open files and null versions for unopened files. It conservatively rejects a new identifier already present in affected source to prevent capture. Standard-library definitions open as read-only compiler source documents in VS Code, with hover and definition/type navigation through their imports and signatures. External declarations cannot be renamed. Malformed workspace source must be repaired before rename.

Content-Length transport limits frames to 16 MiB and headers to 8 KiB. Invalid JSON/parameters receive protocol errors without ending the session. A separate reader accepts request cancellation while analysis runs; canceled requests return `RequestCancelled`. Source changes invalidate dependent open-document diagnostics.

## Linting and formatting

`lint` returns 1 for findings and 0 for clean source. Stable advisory codes are MSL001 (trailing whitespace), MSL002 (missing final newline), MSL101 (unread local or match payload binding; a read inside an assignment to the same variable, as in `total = total + 2`, does not count; use `_` to ignore a payload), MSL102 (unused import), MSL103 (unreachable statement), MSL104 (discarded Result), MSL105 (unsynchronized captured mutation), MSL106 (a match payload binding mistaken for a case or type pattern) MSL107 (nested match) and MSL108 (a match with only some and none arms on an Optional). Semantic rules use checked bindings and control-flow facts. Required implicit imports, such as canonical `List` for list literals, count as uses. Unused-import and whitespace fixes are available in the editor; initializers with possible effects are never silently removed. Run `ms check` for correctness errors.

MSL104 warns when an expression statement discards a standard `Result`. Handle it with `match`, propagate it with `try`, or explicitly bind it as `let _ignored = operation()` when ignoring both success and failure is intentional. See [Result handling](../core-language/errors/results.md).

MSL105 identifies direct mutations of captured data in known concurrent callbacks. It is advisory and does not prove race freedom; use one `Synchronized` wrapper for shared mutable access. See [sharing and lint limits](../concurrency/sharing.md#captured-mutable-data).

MSL106 explains that a capitalized payload name creates a fresh binding even
when it names a known constructor or alternative case. It suggests a separate
helper to match a case of the payload's type, or renaming an intentional binding.
See [payload patterns](../core-language/control-flow/pattern-matching.md#payload-patterns).

MSL108 warns at a match on an Optional whose only arms are `some` and `none`; use `if let` or an Optional method. MSL107 warns at a match nested structurally inside another match. Use an early-exit payload binding, compatible `try`, or a small helper to keep flow flat. It includes inline callbacks beneath an outer match and preserves checking/runtime behavior. See [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

String replacement names remain outside its preference map. In particular,
`String.replace_first` still accepts a cap greater than one; renaming every
`String.replace` call would conceal that behavior. Both names remain supported
with their current signatures; see [replacement limits](../standard-library/data.md).

`fmt` accepts files, directories, and manifests, with project discovery shared with checking. `--check` reports every unformatted file and fails if any target needs formatting or cannot be processed. `--drop-labels` first removes redundant argument labels (`key: key` where the call binds that parameter by position anyway) using the checked program, and reports the first diagnostic and leaves the file untouched when it does not check; with `--check` it reports the files that would change. See [formatting](source/formatting.md) for selection and exclusion rules. It preserves comments and token spellings, validates both input and output, and writes atomically. Formatting and import-organization actions include document versions. Import sorting retains comment and blank-line group boundaries.

The formatter adds single blank lines at structural boundaries so code reads in
paragraphs:

- Separate top-level declarations from each other and from imports. Separate
  implementation methods; keep interface signatures, record fields, and
  alternative cases compact.
- Separate substantial conditionals, loops, resource scopes, and matches from
  neighboring statements. A single-step branch or loop without an `else` stays
  with adjacent work; a block containing multiple statements or a substantial
  nested block gains a paragraph boundary. An `if` with no `else` and exactly
  one `return`, `break`, or `continue` is a guard: keep it with preceding setup and consecutive guards,
  then add a blank line before the next statement.
- Keep each `if`/`else if`/`else` family together. Preserve inline bodies.
- Keep match arms together, including compact indented arms.
- Put inserted breaks before contiguous leading comments at the same indentation,
  keeping those comments with the following code.

These rules also apply inside anonymous functions. Authored blank lines are
discarded; paragraph breaks come from these structural rules. The formatter
does not infer stages from the names of calls or bindings.

Expression layout uses a soft limit of 88 columns:

- Keep calls and signatures on one line when they fit, whatever their argument
  or parameter count, nested calls, compound computations, or defaults. An
  anonymous function whose body is a multi-statement suite always expands its
  call. Include the return type when deciding whether a signature fits,
  excluding callback bodies and enclosing arguments.
- Keep lists, grouped imports, and maps compact when they fit, regardless of
  item count. Later call arguments do not count toward the width of a preceding
  list or call in a chain.
- Pack simple list elements into rows of up to 88 columns when the list wraps.
  Nested groups, expressions, and commented items retain separate lines.
- When other groups expand, put every argument, parameter, or element on its own line.
  Use four spaces beyond the containing line and align the closing delimiter with
  that line. An authored multiline group collapses when it fits and holds no
  comment or suite; an authored trailing comma is dropped when it does.
- Break conditions that exceed the limit at their lowest-precedence logical
  operator. Keep comparison operands together. Long arithmetic and member chains
  also gain continuation lines, preserving precedence and evaluation order.
- Add grouping parentheses around complete statement values, argument values,
  collection elements, and parameter defaults when continuation requires them.
  Keep inline suites, including inline `if`, intact.
- Comments force a group to expand. Keep opener comments on the opener, trailing
  argument comments beside that argument, and leading comments with their item.
  Move anonymous-function bodies with their headers when an argument moves.

String literals, their interpolation text, and comment wording are preserved.
They can exceed the soft limit; the formatter does not split or rewrite them.

## Debugging and profiling

`ms debug` is also available for Delve's terminal UI.

`ms debug --break <location>` and `ms debug --script <file>` are non-interactive and meant for agents and scripts; see [scripted debugging](debugging/debugger-integration.md#scripted-debugging-for-agents).

Profiling is explicit and local: CPU/heap use pprof and execution traces use Go tracing. New files are created exclusively with mode 0600; existing files are never overwritten. Profiles flush before process exit, including handled faults and signal cancellation. A setup or heap-write error returns exit code 70. Only one capture can run at a time in a process. Use optimized builds for representative samples and retain matching native metadata.

Source entry boundaries contribute `ms.source` CPU labels and, when tracing, `source:<position>` regions. Nested calls inherit the entry label and remain visible in sampled CPU stacks through native source mappings; they do not create a label/context/trace region per call. Each task-group or scheduled operation starts a fresh source boundary, with work labels and trace tasks. Joining and lexical cleanup have named trace regions. This coarser attribution reduces instrumentation cost but does not provide a complete per-call timeline. Heap-only capture adds no source instrumentation. Profiling preserves cancellation and work lifetime; ordinary source calls take a single atomic branch.

Profiling still changes execution time and allocation behavior. CPU capture also waits for samples to flush at shutdown, and heap capture forces a garbage collection. Tracing can add substantial time and disk usage, especially with many work operations or allocations. Measure an unprofiled executable separately when comparing performance; neither capture wall time nor instrumented CPU samples establish normal program speed.

The checker analyzes each affected module rather than incrementally reusing individual syntax/type nodes. Public rename is conservative about identifier collisions. The VS Code debugger retains native runtime frames as subdued entries (scripted `ms debug` omits them), and complex watch expressions retain native Go syntax. These behaviors are explicit rather than hidden by unsupported capabilities.

`ms profile module-or-project --out-dir new-directory` captures `cpu.pprof` and `heap.pprof` and retains the optimized executable, build/source metadata, static inspection, and a bundle manifest for reproducible symbolization. `-o` and `--output` remain compatible aliases for `--out-dir`. Add `--trace` to also capture `trace.out`. Trace capture is now opt-in: the default bundle omits the trace file and its manifest entry. Existing directories are rejected. For individual output paths, use the existing `ms run … --cpu-profile path --heap-profile path --trace path` options; every requested output is captured.

```sh
ms profile main.ms --out-dir samples
ms profile main.ms --out-dir traced-samples --trace
ms pprof -top samples/cpu.pprof
ms trace -http=127.0.0.1:8080 traced-samples/trace.out
```
