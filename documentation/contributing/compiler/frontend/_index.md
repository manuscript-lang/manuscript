+++
title = "Parsing and checking"
weight = 1
+++

# Parsing and checking

Before native code generation, `compiler/check` checks names, types, scopes, captures, cleanup, and ownership, and records the facts in typed HIR. `compiler/lower` lowers that HIR to MIR for optimization, verification, and LLVM code generation.

- [Compilation pipeline](pipeline.md): from project loading to native executable.
- [Type checking and source contracts](type-checker.md)
- [Scope and capture checking](scope-checker.md)
- [Typed intermediate representation](typed-ir.md)
