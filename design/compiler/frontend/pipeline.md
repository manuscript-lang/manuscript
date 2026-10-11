+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler design translates Manuscript source into Go while enforcing source contracts that Go alone does not supply. This is an implementation contract for the future compiler.

The compiler is implemented in Go. Parsing, type, scope, and capture checking produce typed intermediate representation with explicit evaluation order, closure captures, cleanup scopes, effects, and source locations. The backend emits one application Go package plus separate adapter interface schema packages, using versioned runtime/native capability packages, then invokes a pinned Go toolchain. Schema packages cannot depend on the application; [adapter bindings](../../modules-and-capabilities/adapters/manifests.md) define the acyclic package direction.

## Following a program through compilation

The compiler first reads the project's `ms.toml`, loads its entry `.ms` file, and discovers modules through relative path imports and optional aliases. Canonical resolved file paths establish module identity. Parsing establishes source structure without module declarations. Import checking resolves exported symbols and rejects dependency cycles; type, scope, and capture checking resolve source types, captures, and scopes. The typed representation records the facts lowering needs to preserve. Emitting and building the application uses the separately versioned runtime and adapters.

The design specifies this pipeline, but does not establish a concrete parser library, AST schema, or internal package layout.

See [project configuration and module paths](../builds/project-configuration.md), [type checking](type-checker.md), [scope and capture checking](scope-checker.md), and [the typed representation](typed-ir.md).

[Next: Type checking and source contracts](../frontend/type-checker.md)
