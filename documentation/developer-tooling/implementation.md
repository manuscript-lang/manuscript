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
ms lsp
ms debug source.ms -- arg1
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

Commands that take one source input also accept a project directory containing
`ms.toml`, including `doc`; native commands select one application entrypoint.
`fmt` selects multiple files or recursively discovers directories as described
in [formatting](source/formatting.md).

## Rebuild on save

```sh
ms run ms.toml --watch -- arg1
ms test test.ms --watch
```

`--watch` keeps one `ms` process alive, rebuilds after each saved change to the manifest or any loaded local module, and restarts the program. The running program is interrupted, given five seconds to finish cleanup, and then killed, but only after its replacement builds; a failed edit prints diagnostics and keeps watching. Each restart reports the time from the save. Interrupting `ms` interrupts the program and exits with status 130. See [cache boundaries](builds/incremental-compilation.md) for what a rebuild still compiles and links.

Project lint checks hygiene in every reachable local module and runs semantic rules on the checked program. [Library projects](builds/project-configuration.md#library-projects-and-copied-dependencies) include all source modules and discovered tests. `--json` reports stable rule codes and module-relative positions.

## Source inspection and API documentation

```sh
ms check ms.toml --json
ms inspect ms.toml -o inspection.json
ms diagram ms.toml -o calls.mmd
ms doc src/library.ms -o api.md
ms doc ms.toml --json -o api.json
ms doc --stdlib -o stdlib.md
ms doc --stdlib --json -o stdlib.json
ms stdlib exported-standard-sources
```

These commands use source checking and embedded declarations without a Go installation or native toolchain extraction. `inspect` retains symbols, local names, call sites, source hashes, statement spans, and conservative effects. `diagram` renders their static call graph as Mermaid; it is not an execution trace.

`doc` checks the input first and documents only its exported declarations, including fields, alternative cases, contract operations, and generic bounds. A contiguous `#` comment block directly above a declaration or member, at the same indentation and with no intervening blank line, is its description. Markdown renders these descriptions beside the corresponding signatures; JSON carries declaration `doc` strings and an additive `members` array with `name`, `kind`, `signature`, `doc`, and an optional implementation `contract`. Existing `fields`, `cases`, and `operations` arrays remain strings under schema version 1. Empty member descriptions stay visible as empty `doc` strings; the tool does not invent text from a signature. Inline case payloads do not inherit the case's description. Project docs include reachable local modules; library projects include all source modules and discovered tests. Private declarations and re-imported standard names are excluded. Without `-o`, output goes to stdout. The `--stdlib` reference and `stdlib` source export describe the compiler version bundled in that binary; neither downloads a library.

`ms stdlib <directory>` writes source declarations and bindings for tooling;
`ms doc --stdlib` renders API documentation. These outputs serve different tasks.

`ms emit ms.toml -o main.go` writes generated Go with the runtime included. Compiling emitted source directly still requires the repository's pinned `go.mod`, `go.sum`, `vendor/` tree, and `internal/hostos/` platform helpers. From a checkout, use `toolchain/go/bin/go build -mod=vendor main.go`. Ordinary `ms build`, `run`, and `test` supply those inputs themselves. See [pins and native builds](builds/reproducibility.md).

## Editor features

The server supports incremental document synchronization with validated UTF-16 ranges, compiler diagnostics and advisory lint codes, hierarchical document symbols, workspace symbol search, semantic tokens, folding, inferred-local type hints, typed hover, definition/type-definition navigation, highlights, project references, signature help, formatting, import organization, and versioned code actions and rename edits.

Completion is derived from the checker's actual lexical scope and member-resolution rules. It resolves shadowing and offers visible parameters/locals, generic-bound operations, substituted record fields and collection/service methods, variant cases, named call arguments, generic/call snippets, standard and project auto-imports, and import names/paths. Used arguments, inaccessible opaque fields, and locals in sibling scopes are excluded. Snippets are offered only when the client supports them. Accepting an auto-import creates an explicit ordinary import.

Incomplete member accesses and calls are analyzed using a private cursor snapshot. Declaration recovery retains unaffected source with original positions. Recovery is exclusive to editor analysis: strict checking, formatting, and native builds never accept repaired source. A parse error elsewhere does not erase completion or outlining for valid declarations. Analysis skips Go lowering and caches normal document results until source or watched files change. Member completion's local benchmark is included in `completion_test.go`.

References and rename cover declaration names, expression uses, assignments, type annotations, imports, named parameter labels, record fields/constructors, and source interface operations. Project scans include unopened modules. Rename checks the proposed workspace snapshot before returning edits and uses document versions for open files and null versions for unopened files. It conservatively rejects a new identifier already present in affected source to prevent capture. Standard-library definitions open as read-only compiler source documents in VS Code, with hover and definition/type navigation through their imports and signatures. External declarations cannot be renamed. Malformed workspace source must be repaired before rename.

Content-Length transport limits frames to 16 MiB and headers to 8 KiB. Invalid JSON/parameters receive protocol errors without ending the session. A separate reader accepts request cancellation while analysis runs; canceled requests return `RequestCancelled`. Source changes invalidate dependent open-document diagnostics.

## Linting and formatting

`lint` returns 1 for findings and 0 for clean source. Stable advisory codes are MSL001 (trailing whitespace), MSL002 (missing final newline), MSL101 (unread local), MSL102 (unused import), MSL103 (unreachable statement), MSL104 (discarded Result), MSL105 (unsynchronized captured mutation), and MSL106 (a match payload binding mistaken for a case or type pattern). Semantic rules use checked bindings and control-flow facts. Required implicit imports, such as canonical `List` for list literals, count as uses. Unused-import and whitespace fixes are available in the editor; initializers with possible effects are never silently removed. Run `ms check` for correctness errors.

MSL104 warns when an expression statement discards a standard `Result`. Handle it with `match`, propagate it with `try`, or explicitly bind it as `let _ignored = operation()` when ignoring both success and failure is intentional. See [Result handling](../core-language/errors/results.md).

MSL105 identifies direct mutations of captured data in known concurrent callbacks. It is advisory and does not prove race freedom; use one `Synchronized` wrapper for shared mutable access. See [sharing and lint limits](../concurrency/sharing.md#captured-mutable-data).

MSL106 explains that a capitalized payload name creates a fresh binding even
when it names a known constructor or alternative case. It suggests a separate
helper to match a case of the payload's type, or renaming an intentional binding.
See [payload patterns](../core-language/control-flow/pattern-matching.md#payload-patterns).

`fmt` accepts files, directories, and manifests, with project discovery shared with checking. `--check` reports every unformatted file and fails if any target needs formatting or cannot be processed. See [formatting](source/formatting.md) for selection and exclusion rules. It preserves comments and token spellings, validates both input and output, and writes atomically. Formatting and import-organization actions include document versions. Import sorting retains comment and blank-line group boundaries.

The formatter adds single blank lines at structural boundaries so code reads in
paragraphs:

- Separate top-level declarations from each other and from imports. Separate
  implementation methods; keep interface signatures, record fields, and
  alternative cases compact.
- Separate conditionals, loops, resource scopes, and matches from neighboring
  statements. An `if` with no `else` and exactly one `return`, `break`, or
  `continue` is a guard: keep it with preceding setup and consecutive guards,
  then add a blank line before the next statement.
- Keep each `if`/`else if`/`else` family together. Preserve inline bodies.
- Preserve authored spacing between match arms, including compact indented arms.
- Put inserted breaks before contiguous leading comments at the same indentation,
  keeping those comments with the following code.

These rules also apply inside anonymous functions. Existing paragraph breaks are
preserved, with consecutive blank lines reduced to one. The formatter does not
infer stages from the names of calls or bindings.

Expression layout uses a soft limit of 88 columns:

- Keep simple calls and small literals compact. Expand calls with four or more
  arguments, multiple arguments containing nested calls or compound computations,
  or a closure argument. Single-argument calls containing another nested
  computation can also expand.
- Expand signatures with four or more parameters or complex defaults. Include the
  return type when deciding whether a signature fits, excluding callback bodies
  and enclosing arguments.
- Keep lists compact when they fit, including nested lists. Expand grouped
  imports with five or more names. Later call arguments do not count toward
  the width of a preceding list or call in a chain.
- Once a group expands, put every argument, parameter, or element on its own line.
  Use four spaces beyond the containing line and align the closing delimiter with
  that line. Existing multiline groups remain expanded with this same layout.
- Break conditions with three or more clauses at their lowest-precedence logical
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

`ms debug` is also available for Delve's terminal UI. Existing project pin validation remains in effect; use `ms lock ms.toml` explicitly after a toolchain/compiler change.

Profiling is explicit and local: CPU/heap use pprof and execution traces use Go tracing. New files are created exclusively with mode 0600; existing files are never overwritten. Profiles flush before process exit, including handled faults and signal cancellation. Source functions contribute `ms.source` CPU labels and `source:<position>` trace regions. Task-group/scheduled operations contribute work labels and trace tasks; joining and lexical cleanup have named trace regions. Profiling preserves authority, cancellation, and work lifetime. Without profiling, source calls take a single atomic branch. A setup or heap-write error returns exit code 70. Use optimized builds for representative samples and retain matching native metadata.

The checker analyzes each affected module rather than incrementally reusing individual syntax/type nodes. Public rename is conservative about identifier collisions. The debugger retains native runtime frames as subdued entries, and complex watch expressions retain native Go syntax. These behaviors are explicit rather than hidden by unsupported capabilities.

`ms profile module-or-project -o new-directory` captures all three profiles and retains the optimized executable, build/source metadata, static inspection, and a bundle manifest for reproducible symbolization. Existing directories are rejected.
