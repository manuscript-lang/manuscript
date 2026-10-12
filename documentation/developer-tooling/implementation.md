+++
title = "Tooling commands and limits"
weight = 1
+++

# Manuscript developer tools

Use a self-contained `ms` binary from [Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases), or run `make build` in a source checkout to prepare the pinned Go SDK automatically. Compilation, formatting, lint, LSP, and profiling need no separate Go installation. Native debugging uses Delve 1.25.2 or newer, available from [Delve Releases](https://github.com/go-delve/delve/releases). The VS Code extension provides its own Manuscript DAP layer over Delve.

```sh
ms lint source.ms --json
ms lint ms.toml --json
ms fmt source.ms --check
ms lsp
ms debug source.ms -- arg1
ms run source.ms --cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out -- arg1
go tool pprof -tags cpu.pprof
go tool pprof -http=127.0.0.1:8080 cpu.pprof
go tool trace trace.out
```

Project lint checks hygiene in every reachable local module and runs semantic rules on the checked program. `--json` reports stable rule codes and module-relative positions.

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

`doc` checks the input first and documents only its exported declarations, including fields, alternative cases, contract operations, and generic bounds. Project docs include reachable local modules. Private declarations and re-imported standard names are excluded. Without `-o`, output goes to stdout. JSON uses schema version 1. The `--stdlib` reference and `stdlib` source export describe the compiler version bundled in that binary; neither downloads a library.

`ms emit ms.toml -o main.go` writes generated Go with the runtime included. Compiling emitted source directly still requires the repository's pinned `go.mod`, `go.sum`, `vendor/` tree, and `internal/hostos/` platform helpers. From a checkout, use `toolchain/go/bin/go build -mod=vendor main.go`. Ordinary `ms build`, `run`, and `test` supply those inputs themselves. See [pins and native builds](../compiler/builds/reproducibility.md).

## Editor features

The server supports incremental document synchronization with validated UTF-16 ranges, compiler diagnostics and advisory lint codes, hierarchical document symbols, workspace symbol search, semantic tokens, folding, inferred-local type hints, typed hover, definition/type-definition navigation, highlights, project references, signature help, formatting, import organization, and versioned code actions and rename edits.

Completion is derived from the checker's actual lexical scope and member-resolution rules. It resolves shadowing and offers visible parameters/locals, generic-bound operations, substituted record fields and collection/service methods, variant cases, named call arguments, generic/call snippets, standard and project auto-imports, and import names/paths. Used arguments, inaccessible opaque fields, and locals in sibling scopes are excluded. Snippets are offered only when the client supports them. Accepting an auto-import creates an explicit ordinary import.

Incomplete member accesses and calls are analyzed using a private cursor snapshot. Declaration recovery retains unaffected source with original positions. Recovery is exclusive to editor analysis: strict checking, formatting, and native builds never accept repaired source. A parse error elsewhere does not erase completion or outlining for valid declarations. Analysis skips Go lowering and caches normal document results until source or watched files change. Member completion's local benchmark is included in `completion_test.go`.

References and rename cover declaration names, expression uses, assignments, type annotations, imports, named parameter labels, record fields/constructors, and source interface operations. Project scans include unopened modules. Rename checks the proposed workspace snapshot before returning edits and uses document versions for open files and null versions for unopened files. It conservatively rejects a new identifier already present in affected source to prevent capture. Standard-library definitions open as read-only compiler source documents in VS Code, with hover and definition/type navigation through their imports and signatures. External declarations cannot be renamed. Malformed workspace source must be repaired before rename.

Content-Length transport limits frames to 16 MiB and headers to 8 KiB. Invalid JSON/parameters receive protocol errors without ending the session. A separate reader accepts request cancellation while analysis runs; canceled requests return `RequestCancelled`. Source changes invalidate dependent open-document diagnostics.

## Linting and formatting

`lint` returns 1 for findings and 0 for clean source. Stable advisory codes are MSL001 (trailing whitespace), MSL002 (missing final newline), MSL101 (unread local), MSL102 (unused import), and MSL103 (unreachable statement). Semantic rules use checked bindings and control-flow facts. Required implicit imports, such as canonical `List` for list literals, count as uses. Unused-import and whitespace fixes are available in the editor; initializers with possible effects are never silently removed. Run `ms check` for correctness errors.

`fmt` preserves comments and token spellings, validates both input and output, and writes atomically. Formatting and import-organization actions include document versions. Import sorting retains comment and blank-line group boundaries.

## Debugging and profiling


`ms debug` is also available for Delve's terminal UI. Existing project pin validation remains in effect; use `ms lock ms.toml` explicitly after a toolchain/compiler change.

Profiling is explicit and local: CPU/heap use pprof and execution traces use Go tracing. New files are created exclusively with mode 0600; existing files are never overwritten. Profiles flush before process exit, including handled faults and signal cancellation. Source functions contribute `ms.source` CPU labels and `source:<position>` trace regions. Task-group/scheduled operations contribute work labels and trace tasks; joining and lexical cleanup have named trace regions. Profiling preserves authority, cancellation, and work lifetime. Without profiling, source calls take a single atomic branch. A setup or heap-write error returns exit code 70. Use optimized builds for representative samples and retain matching native metadata.

The checker analyzes each affected module rather than incrementally reusing individual syntax/type nodes. Public rename is conservative about identifier collisions. The debugger retains native runtime frames as subdued entries, and complex watch expressions retain native Go syntax. These behaviors are explicit rather than hidden by unsupported capabilities.

`ms profile module-or-project -o new-directory` captures all three profiles and retains the optimized executable, build/source metadata, static inspection, and a bundle manifest for reproducible symbolization. Existing directories are rejected.
