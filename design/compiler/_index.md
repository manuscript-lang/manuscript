+++
title = "Compiler design"
weight = 86
+++

# Compiler design guide

[Design index](../_index.md)

Read the implementation contract from checked source through typed representation, Go lowering, builds, and conformance evidence.

## Reading order

### 1. [Parsing and checking](frontend/_index.md)

- [Compilation pipeline](frontend/pipeline.md)
- [Type checking and source contracts](frontend/type-checker.md)
- [Scope and capture checking](frontend/scope-checker.md)
- [Typed intermediate representation](frontend/typed-ir.md)

### 2. [Go lowering](lowering/_index.md)

- [Function and concurrency API lowering](lowering/function-and-task-calls.md)
- [Source guarantees and Go representations](lowering/value-representations.md)
- [Evaluation order and call preparation](lowering/evaluation-order.md)
- [Cleanup and fault lowering](lowering/cleanup-and-faults.md)

### 3. [Builds and dependencies](builds/_index.md)

- [Project configuration and module paths](builds/project-configuration.md)
- [Pinned dependencies and deterministic output](builds/reproducibility.md)
- [Caching and Go package boundaries](builds/incremental-compilation.md)

### 4. [Conformance and scope](conformance/_index.md)

- [Semantic conformance tests](conformance/semantic-tests.md)
- [Complete-program conformance](conformance/programs.md)
- [Scope and implementation order](conformance/scope.md)
