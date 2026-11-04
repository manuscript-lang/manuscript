+++
title = "Start here"
weight = 2
+++

# Start here

Run a program, learn the language, then build something useful. Start with the compiler setup and an Internet connection for its first build.

## New to Manuscript?

[Why Manuscript](why-manuscript.md) is a one-page summary of what makes it worth trying.

1. **[Run your first program](getting-started.md).** Install `ms` and build an executable.
2. **[Take the language tour](tour.md).** Bindings, collections, functions, types, errors, modules.
3. **[Test your code](testing.md).** Write tests and run the cases you want.
4. **[Write idiomatic Manuscript](best-practices.md).** Control flow, errors, ownership, resources.
5. **[Build a small tool](common-tasks.md).** Start from a complete arguments, files, JSON, or HTTP recipe.

Read in order with **Next**. Local statements in examples belong inside a function or test.

## Ready to build?

[Task recipes](common-tasks.md) are complete programs: arguments, files, JSON, and HTTP. [Developer tools](../developer-tooling/_index.md) cover editor setup, builds, and debugging.

## Need an exact answer?

- [Language reference](../core-language/_index.md): syntax and semantics
- [API reference](../standard-library/reference/_index.md): signatures and behavior
- [Glossary](../glossary.md): unfamiliar terms

## Find an API without leaving the terminal

Run these from your project directory:

```sh
ms search_symbol read file
ms search_symbol json
ms search_symbol PromiseOptions
```

Search includes project symbols and the bundled standard library. A module query such as `json` shows its API page; a specific name narrows the output. Use the [API reference](../standard-library/reference/_index.md) for browsing, and the [language reference](../core-language/_index.md) for rules such as borrowing and cleanup.

## Working with a coding agent?

Point it at `ms guide` and `ms search_symbol <name or words>`. Use `ms verify` for check, formatting, lint, and tests together; `ms check --json` gives structured diagnostics, and `ms check --fix` applies available mechanical fixes. See [commands for agents](../developer-tooling/implementation.md#commands-for-agents).
