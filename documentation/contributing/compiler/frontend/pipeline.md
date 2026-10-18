+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

The compiler turns Manuscript source into Go and builds it natively. It checks Manuscript's own rules first; Go accepting the output does not validate the source.

1. **Load the project.** Read `ms.toml`, find the entry `.ms` file, follow imports, and map paths and aliases to canonical file identities.
2. **Parse.** Read declarations, expressions, and indented blocks. Each file is a module and needs no `module` declaration.
3. **Resolve imports and names.** Find exports and reject import cycles.
4. **Check.** Validate types, scopes, captures, and source contracts.
5. **Record facts.** Produce typed IR: evaluation order, captures, cleanup scopes, effects, source locations.
6. **Generate Go and build** with the pinned toolchain, versioned runtime, and adapters.

The compiler is written in Go and emits one application Go package. External adapters remain design work; the [repository architecture](../../architecture.md) describes the current layout.

Continue with [project configuration](../../../developer-tooling/builds/project-configuration.md), [type checking](type-checker.md), [scope and capture checking](scope-checker.md), and [typed IR](typed-ir.md).
