+++
title = "Start here"
weight = 2
+++

# Start here

Run a program, learn the language, then build something useful. The same `ms` command helps you write, test, understand and ship your code.

## New to Manuscript?

[Why Manuscript](why-manuscript.md) follows an agent building a program, from first mistake to shipped executable. Know TypeScript, Go or Python? See [coming from another language](../coming-from/_index.md).

1. **[Run your first program](getting-started.md).** Install `ms` and build an executable.
2. **[Take the language tour](tour.md).** Bindings, collections, functions, types, errors, modules.
3. **[Test your code](testing.md).** Write tests and run the cases you want.
4. **[Build a small tool](common-tasks.md).** Start from a complete arguments, files, JSON, or HTTP recipe.

Read in order with **Next**.

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

The `PromiseOptions` search starts with:

```text
promise.PromiseOptions  record  std:@std/concurrency/promise.ms
  type PromiseOptions: timeout: Duration? = none cancel: Signal? = none
```

It also lists matching fields and related functions. Search includes project symbols and the bundled standard library. A module query such as `json` shows its API page; a specific name narrows the output. Use the [API reference](../standard-library/reference/_index.md) for browsing, and the [language reference](../core-language/_index.md) for rules such as borrowing and cleanup.

## Working with a coding agent?

Point it at `ms guide` and `ms search_symbol <name or words>`. Use `ms verify` for type checking, formatting checks, lint, and tests together; `ms check --json` gives structured diagnostics, and `ms check --fix` applies available mechanical fixes. See [commands for agents](../developer-tooling/implementation.md#commands-for-agents).
