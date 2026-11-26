+++
title = "Compilation pipeline"
weight = 88
+++

# Compilation pipeline

The compiler turns Manuscript source into native code through LLVM IR and the pinned LLVM tools. It checks Manuscript's own rules first.

1. **Load the project.** Read `ms.toml`, find the entry `.ms` file, follow imports, and map paths and aliases to canonical file identities.
2. **Parse.** Read declarations, expressions, and braced blocks. Each file is a module and needs no `module` declaration.
3. **Resolve imports and names.** Find exports and reject import cycles.
4. **Check.** Validate types, scopes, captures, and source contracts.
5. **Record facts.** Produce typed IR: evaluation order, captures, cleanup scopes, effects, source locations.
6. **Lower, generate code, and link** MIR as LLVM IR against the embedded native runtime.

When narrowing a failure, use `ms check` to separate loading and checking from native compilation. `ms build --emit mir` goes through lowering and prints MIR; `ms run` also generates, links and executes native code. Keep the smallest source program that distinguishes the failing stage. The [repository architecture](../../architecture.md) maps these stages to the source layers.

Continue with [project configuration](../../../developer-tooling/builds/project-configuration.md), [type checking](type-checker.md), [scope and capture checking](scope-checker.md), and [typed IR](typed-ir.md).
