+++
title = "Language guide and reference"
weight = 2
+++

# Language guide and reference

Learn how to build programs from values, functions, and types, then connect them to files, modules, and concurrent work. Each chapter explains a concept and keeps its precise rules nearby. Start with [your first program](../learn/getting-started.md) and the [language tour](../learn/tour.md) if you have not run Manuscript yet.

## Read the language guide

Follow this path for a first reading. You can return to individual chapters when a program needs a particular feature:

1. [Basics](basics/_index.md): source files, variables, numbers, text, and expressions.
2. [Functions](functions/_index.md): parameters, calls, and closures.
3. [Types](types/_index.md): records, enums, collections, and interfaces.
4. [Control flow](control-flow/_index.md): conditions, loops, and matching.
5. [Error handling](errors/_index.md): results, propagation, and faults.
6. [Modules](modules/_index.md): imports, exports, and public boundaries.
7. [Managing resources](cleanup/_index.md): closing files and connections when their scope ends.
8. [Concurrent tasks](concurrency/_index.md): running work at once with promises.

Find declarations in the generated [standard-library API reference](../standard-library/reference/_index.md).

## Follow a question into the rules

When a call is surprising, start with [argument binding and defaults](functions/declarations-and-calls.md), then [type compatibility](types/compatibility.md). When data cannot be changed or kept, follow [ownership and borrowing](types/references.md) and [resource cleanup](cleanup/_index.md). These explain the rules in the language itself; reading compiler source is not a prerequisite.

Use the [source grammar](basics/grammar.md) for exact syntax, [operator rules](basics/expressions.md) for precedence and evaluation, and [module boundaries](modules/boundaries.md) for exported contracts. The [glossary](../glossary.md) connects terminology to these chapters.

## Put the pieces to work

[Task recipes](../learn/common-tasks.md) and [library lessons](../recipes/_index.md) combine the language with the bundled APIs. [Developer tools](../developer-tooling/_index.md) explain how to check, test, build, and inspect those programs. [Contributor documentation](../contributing/_index.md) is for working on the compiler and repository itself.
