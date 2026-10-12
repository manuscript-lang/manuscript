+++
title = "Compiler design"
weight = 86
+++

# Compiler design guide

[Design index](../_index.md)

This chapter is for compiler contributors and readers who need to understand builds. Follow a program from parsing and checking to generated Go, then read how builds are pinned and tested. For ordinary application code, you can start with [project configuration](builds/project-configuration.md).

## Reading order

### 1. [Parsing and checking](frontend/_index.md)

- [Compilation pipeline](frontend/pipeline.md) — Follow a program from project loading to the native executable.
- [Type checking and source contracts](frontend/type-checker.md)
- [Scope and capture checking](frontend/scope-checker.md)
- [Typed intermediate representation](frontend/typed-ir.md)

### 2. [Go lowering](lowering/_index.md)

- [Function and concurrency API lowering](lowering/function-and-task-calls.md)
- [Source guarantees and Go representations](lowering/value-representations.md)
- [Evaluation order and call preparation](lowering/evaluation-order.md)
- [Cleanup and fault lowering](lowering/cleanup-and-faults.md)

### 3. [Builds and dependencies](builds/_index.md)

- [Project configuration and module paths](builds/project-configuration.md) — Set the source directory, entry file, and import paths in `ms.toml`.
- [Pinned dependencies and deterministic output](builds/reproducibility.md) — Record versions and inputs so builds use the intended distribution.
- [Caching and Go package boundaries](builds/incremental-compilation.md) — Understand what can be cached and when Go must rebuild a package.

### 4. [Conformance and scope](conformance/_index.md)

- [Core-language fixtures](conformance/core-language.md) — Check complete modules and rejected variants.
- [Runtime binding fixtures](conformance/runtime-bindings.md) — Check standard imports, sharing, and host bindings.

- [Semantic conformance tests](conformance/semantic-tests.md) — Test required behavior, including cancellation races and cleanup.
- [Complete-program conformance](conformance/programs.md) — Check that guarantees work together in complete applications.
- [Scope and implementation order](conformance/scope.md) — Find remaining decisions and the order in which work depends on them.
