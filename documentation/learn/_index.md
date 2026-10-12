+++
title = "Learn Manuscript"
weight = 2
+++

# Learn Manuscript

Manuscript combines static types and native executables with code that makes dependencies and execution easy to follow. Public signatures state their contracts; local types can be inferred. Calls to functions with multiple parameters name their arguments; single-parameter calls may omit the label. Expected failures are values, resources have lexical cleanup, and concurrency is explicit.

This introduction follows the example-first approach of [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/) and [A Tour of Go](https://go.dev/tour/): run a small program, learn a few reusable concepts, then consult the reference for exact rules. Manuscript has its own syntax and semantics.

1. [Get started](getting-started.md): build the compiler and run a native application.
2. [A language tour](tour.md): read functions, data, branching, and errors.
3. [Features and boundaries](features.md): understand cleanup, concurrency, and explicit authority.
4. [Module reference](../standard-library/reference/_index.md): look up every implemented standard export and operation.

The compiler is under active development. [Implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/documentation/implementation.md) separates working features from remaining design work. The detailed design chapters remain the home for exact language rules.
