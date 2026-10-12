+++
title = "Manuscript"
weight = 1
bookToC = false
description = "Write command-line tools, process data, and build services. Manuscript gives you typed functions, mutable collections, explicit error handling, and automatic cleanup for scoped resources."
+++

{{< docs-home >}}

## Start writing

Manuscript is a statically typed language for native programs. Functions declare their inputs and results; local variables can infer their types. Records and collections are mutable, expected errors are `Result` values, and `with` closes scoped resources. Ordinary functions run sequentially; library APIs start concurrent work.

[Run your first program](learn/getting-started.md), then take the [language tour](learn/tour.md).

## Find an answer

| Task | Guide |
| --- | --- |
| Look up syntax and types | [Language](core-language/_index.md) |
| Find a library function | [API reference](standard-library/reference/_index.md) |
| Work with files and connections | [Managing resources](core-language/cleanup/_index.md) |
| Run work concurrently | [Concurrent work](concurrency/_index.md) |
| Organize an application | [Modules](core-language/modules/declarations.md) |
| Format, test, and inspect code | [Developer tools](developer-tooling/_index.md) |

Examples with local statements belong inside a function or test. Blocks marked “Rejected” explain a compiler error; other examples show the usual path.

API downloads: [Markdown](/stdlib.md) · [JSON](/stdlib.json) · [LLM index](/llms.txt).
