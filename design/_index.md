+++
title = "Manuscript"
weight = 1
+++

# Learn Manuscript


Manuscript is a statically typed programming language. You write `.ms` files, and the compiler turns them into Go programs that run as native executables. The language makes function inputs, errors, resource cleanup, and concurrent work explicit so people can follow what a program does.

## Start here

If this is your first visit, follow this path:

1. [Build and run your first program](getting-started.md). Run the included example and understand each line.
2. [Learn the basics](core-language/basics/_index.md). Read source files, name values, and use expressions.
3. [Write functions](core-language/functions/_index.md). Declare inputs and outputs, then call functions with named arguments.
4. [Model data](core-language/types/_index.md) and [choose what runs](core-language/control-flow/_index.md). Use records, alternatives, conditions, and loops.
5. [Handle expected errors](core-language/errors/_index.md). Return a `Result`, handle it with `match`, or pass an error back with `try`.

For a shorter introduction, take the [language tour](learn/tour.md) and read [features and boundaries](learn/features.md). The [learning guide](learn/_index.md) collects those lessons.

Keep the [plain-language glossary](glossary.md) nearby when a term is unfamiliar. You can skip the grammar and compiler chapters until you need an exact rule or implementation detail.

## Find what you need

| I want to… | Read this |
| --- | --- |
| Learn the language | [Core language](core-language/_index.md) |
| Find a standard type or function | [Standard library](standard-library/_index.md) and [generated module reference](standard-library/reference/_index.md) |
| Close files and other resources reliably | [Resource lifetimes and cleanup](ownership-and-cleanup/_index.md) |
| Run operations concurrently or in the background | [Concurrency](concurrency/_index.md) |
| Split code into files and pass access to external services | [Modules and capabilities](modules-and-capabilities/_index.md) |
| Understand checking, generated Go, or build settings | [Compiler design](compiler/_index.md) |
| Format code, inspect diagrams, or understand debugging plans | [Developer tooling](developer-tooling/_index.md) |

## What to expect from the language

A file is a module. It imports the declarations it needs and exports the declarations other files may use. Most standard-library names need an explicit import; a small set of basic types is available everywhere.

Functions declare their parameter and return types. Local variables can infer their types from their initial values. Every supplied argument has a name, such as `welcome(name: "Ada")`.

Calls run sequentially unless you explicitly start concurrent work. Every function can wait for an operation to finish; there is no separate `async` function syntax. Parallel calls wait for all their started operations before returning. Background work belongs to a service with a fixed lifetime.

Expected failures are values that callers can inspect. A `with` block closes its registered resource when the block ends, including when an error or cancellation ends it early. Access to files, networks, and other external services comes through explicit parameters.

The language has one canonical syntax and formatter. Tooling derives architecture and flow diagrams from checked source.

## Design and implementation status

This book describes Manuscript 0.1. The repository contains a working compiler, runtime, command-line tool, and executable tests. Some adapter and tooling features are still design work. Check [implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/IMPLEMENTATION.md) before relying on a feature. [Scope and implementation order](compiler/conformance/scope.md) lists remaining decisions.

The detailed rules on each concept page define how that feature must behave. Test fixtures show how to check those rules. A fixture that merely declares a function proves that the compiler accepts it; runtime behavior needs a test that actually calls it.

## How to read examples

The [first-program guide](getting-started.md) contains a complete runnable module. Other pages often show only the part of a function that explains a concept. Put those fragments inside a function or test; local statements are not allowed at the top of a file.

Short examples may omit imports. Import every standard name that your full module uses; [standard imports](standard-library/types/prelude.md) lists the paths. Examples labeled “rejected” show code the compiler must refuse. Blocks showing standard declarations describe the library API rather than declarations you should copy into an application.

## Reference for tools

The implemented standard library is also available as [plain Markdown](/stdlib.md) and [structured JSON](/stdlib.json), with an [LLM index](/llms.txt). These exports describe the compiler-bundled APIs.

## Historical reviews

The [language completeness review](reviews/language-completeness.md) and [Claude Code review](reviews/claude-design-review.md) record earlier drafts and fixes. Use the current concept pages for today's rules.
