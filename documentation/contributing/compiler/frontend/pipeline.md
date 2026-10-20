+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

The compiler turns Manuscript source into native code through Cranelift. It checks Manuscript's own rules first.

1. **Load the project.** Read `ms.toml`, find the entry `.ms` file, follow imports, and map paths and aliases to canonical file identities.
2. **Parse.** Read declarations, expressions, and indented blocks. Each file is a module and needs no `module` declaration.
3. **Resolve imports and names.** Find exports and reject import cycles.
4. **Check.** Validate types, scopes, captures, and source contracts.
5. **Record facts.** Produce typed IR: evaluation order, captures, cleanup scopes, effects, source locations.
6. **Lower, generate code, and link** MIR with Cranelift against the embedded native runtime.

The compiler is written in Rust. External adapters remain design work; the [repository architecture](../../architecture.md) describes the current layout.

Continue with [project configuration](../../../developer-tooling/builds/project-configuration.md), [type checking](type-checker.md), [scope and capture checking](scope-checker.md), and [typed IR](typed-ir.md).
