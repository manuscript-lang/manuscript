+++
title = "Parsing and checking"
weight = 87
+++

# Parsing and checking

[Guide index](../_index.md) · [Design index](../../_index.md)

Before generating Go, the compiler reads the source and checks names, types, scopes, and captured values. It records the checked facts in a typed intermediate representation, or typed IR. These pages explain each stage.

- [Compilation pipeline](pipeline.md) — Follow a program from project loading to the native executable.
- [Type checking and source contracts](type-checker.md)
- [Scope and capture checking](scope-checker.md)
- [Typed intermediate representation](typed-ir.md)
