+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler turns Manuscript source into Go, then uses Go to build a native executable. Before generating code, it checks Manuscript's own rules; Go accepting the generated program is not enough to prove the source is valid.

## Following a program through compilation

1. **Load the project.** Read `ms.toml`, locate the entry `.ms` file, and follow imports. Resolve relative paths and aliases to canonical file identities so different spellings of one path identify the same module.
2. **Parse the source.** Read declarations, expressions, and indented blocks. Each file is already a module; it needs no `module` declaration.
3. **Resolve imports and names.** Find exported declarations and reject module dependency cycles.
4. **Check the program.** Validate types, scopes, captured values, and source contracts.
5. **Record checked facts.** Produce a typed intermediate representation, or typed IR. It records evaluation order, closure captures, cleanup scopes, effects, and source locations.
6. **Generate Go and build.** Translate those facts into Go and invoke the pinned Go toolchain with the versioned runtime and adapters.

## Package boundaries in the design

The compiler is written in Go. The backend design emits one application Go package and separate packages for adapter interface schemas. Schema packages cannot depend on the application package; see [adapter bindings](../../modules-and-capabilities/adapters/manifests.md) for the dependency direction.

This page defines required behavior. It does not prescribe a parser library, syntax-tree schema, or internal package layout. External adapters remain design work; [implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/documentation/implementation.md) identifies the working compiler's limits.

Continue with [project configuration](../builds/project-configuration.md), [type checking](type-checker.md), [scope and capture checking](scope-checker.md), and [typed IR](typed-ir.md).

[Next: Type checking and source contracts](type-checker.md)
