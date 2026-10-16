---
name: compiler
description: Implement or review Manuscript syntax nodes, lexer/parser, checking, module resolution, Go lowering, metadata, native builds, cache identity, and bundled toolchains.
---

# Compiler

Use for `pkg/syntax/`, `pkg/lexer/`, `pkg/parser/`, `pkg/frontend/`, `pkg/checker/`, `pkg/lower/`, `pkg/compiler/`, `pkg/build/`, `pkg/project/`, or embedded build inputs. Read [architecture](../../documentation/contributing/architecture.md), relevant [compiler rules](../../documentation/contributing/compiler/_index.md), and [language](../../.experts/language.md) / [compiler lessons](../../.experts/compiler.md); syntax work also reads the [grammar](../../documentation/core-language/basics/grammar.md) and [editor recovery lessons](../../.experts/tooling-and-docs.md#editor-recovery-must-preserve-delimiter-continuations).

- Trace `CompileSource`/`CompileFile` through resolution, `checker.Program`, and Go generation. Keep parse/resolution/type/lowering diagnostics attributable to source.
- Preserve source-only analysis: `AnalyzeOnly` stops before lowering; recovery is editor analysis and diagnostics prevent executable generation. Entry validation independently checks `export fn main() -> Int`.
- Resolve nominal symbols, implementations, defaults, and effects in checking; reuse checked identities in consumers. Do not infer semantics from spelling or import the host runtime into the frontend.
- Retain module-local implementation selection through views, bound methods, generics, and cleanup. Defaults must not survive mutable callable replacement or generic inference as omission permissions.
- Keep manifest/alias/path/overlay identity in `pkg/project/`. Resolver changes need symlinked roots, confined unsaved files, dangling links, conflicting overlays, and malformed nested manifest cases.
- Respect the [layers](../../documentation/contributing/architecture.md#respect-the-layers): `lower` has no native tools and no runtime import, and `scripts/repo-check/policy.json` enforces the edges.
- Lower in source evaluation order, including defaults and cleanup on every exit. Check metadata/source maps when emitted code changes; use [runtime](../runtime/SKILL.md) for execution contracts.
- Generated Go is typed Go: each Manuscript type has one Go type, with no universal value or boxing ([representation](../../documentation/contributing/go-lowering-representation.md)). The [lowering page](../../documentation/contributing/compiler/lowering/_index.md) records the rest: `try` is a Go error return, defaults are evaluated by the callee (`rt.Arg`), fault frames come from the Go stack and `//line` directives (no per-call `defer`), and generic instances resolve contract evidence in the instantiating module. Do not add per-call bookkeeping or a second representation back. Measure with `scripts/bench-lowering` and allocation counts, and write the AGENTS.md proposal with an independent skeptical review before changing fault-frame, cancellation, dispatch, or representation semantics.
- Embedded implementation, bindings, dependencies, toolchains, targets, and build levels participate in pin identity; debuggable artifacts also depend on source roots. Built executables are not cached: builds reuse the shared native workspace, Go's package cache, and replay profiles. Keep standalone import aliases consistent and build the temporary module as a module.
- Choose the right algorithm and data structure: passes stay linear (or n log n) in source size. Share visited sets/memos across roots, index instead of rescanning, and avoid per-byte or per-query allocation. Time `ms check`, `ms emit`, and `ms build` at N/2N/4N and profile anything above 2x per doubling; see [the lesson](../../.experts/compiler.md#compiler-passes-use-the-right-algorithm-and-data-structure-for-their-input-size).
- Run affected checker/compiler/project tests and `make repo-check`; execute changed semantics through called `tests/e2e` cases. Build/cache/toolchain changes need artifact evidence and applicable `make dist-check`. Declaration-only acceptance does not establish execution.

## Syntax and parsing

- `pkg/syntax/ast.go` owns the untyped tree and positions; checked semantics belong in `pkg/checker/`. Keep syntax independent of compiler/runtime/editor machinery.
- Update `pkg/syntax/kinds.go` alongside parser, checker, lowering, formatting, and inspection consumers. `make repo-check` checks exhaustive checked/lowered kinds and package dependencies.
- Use `syntax.Visitor` in `pkg/syntax/walk.go` for executable traversal: defaults, interpolation, collections, closures, branches, and match bodies in source order. Do not manufacture statements to visit defaults. Types/patterns need separate handling.
- Preserve file identity and original offset/line/column positions. Check LF/CRLF and editor position conversion when slicing/recovery changes; synthetic repairs must not shift valid declarations.
- Exercise strict `parser.Parse` and editor `parser.ParsePartial`. Incomplete neighboring declarations must not erase multiline parameters or scopes. Use lexer continuation boundaries instead of splitting at lines/closing delimiters.
- Inline suites stop at enclosing delimiters, implicitly return expressions only in callable bodies, and enforce one statement/conditional branch per line. Follow current grammar rather than restoring blanket indentation restrictions.
- Route new shapes through [tooling](../tooling/SKILL.md). Verify traversal, accepted/rejected parsing, recovery, formatting idempotence, and affected editor scopes/navigation. New parsing boundaries merit `FuzzParse`/`FuzzParsePartial`; preserve reproducible failures as regressions.
