---
name: compiler
description: Implement or review Manuscript checking, module resolution, Go lowering, metadata, native builds, cache identity, and bundled toolchains.
---

# Compiler

Use for `pkg/checker/`, `pkg/compiler/`, `pkg/project/`, or embedded build inputs. Read [architecture](../../documentation/contributing/architecture.md), relevant [compiler rules](../../documentation/compiler/_index.md), and [language](../../.experts/language.md) / [build lessons](../../.experts/tooling-and-docs.md).

- Trace `CompileSource`/`CompileFile` through resolution, `checker.Program`, and Go generation. Keep parse/resolution/type/lowering diagnostics attributable to source.
- Preserve source-only analysis: `AnalyzeOnly` stops before lowering; recovery is editor analysis and diagnostics prevent executable generation. Entry validation independently checks `export fn main() -> Int`.
- Resolve nominal symbols, implementations, defaults, and effects in checking; reuse checked identities in consumers. Do not infer semantics from spelling or import the host runtime into the frontend.
- Retain module-local implementation selection through views, bound methods, generics, and cleanup. Defaults must not survive mutable callable replacement or generic inference as omission permissions.
- Keep manifest/alias/path/overlay identity in `pkg/project/`. Resolver changes need symlinked roots, confined unsaved files, dangling links, conflicting overlays, and malformed nested manifest cases.
- Lower in source evaluation order, including defaults and cleanup on every exit. Check metadata/source maps when emitted code changes; use [runtime](../runtime/SKILL.md) for execution contracts.
- Embedded implementation, bindings, dependencies, toolchains, targets, and build levels participate in pin/cache identity; debuggable artifacts also depend on source roots. Keep standalone import aliases consistent and build the temporary module as a module.
- Run affected checker/compiler/project tests and `make repo-check`; execute changed semantics through called `tests/e2e` cases. Build/cache/toolchain changes need artifact evidence and applicable `make dist-check`. Declaration-only acceptance does not establish execution.
