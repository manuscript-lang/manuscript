+++
title = "Start here"
weight = 2
+++

# Start here

Review an agent’s code by running a small example; Manuscript is in alpha, and syntax and APIs may change.

<!-- manuscript-example: {"mode":"run","filename":"hello.ms","stdout":"Ready to review\n"} -->
```manuscript {filename="hello.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

```sh
ms run hello.ms
```

```text
Ready to review
```

- [Install `ms` and build your first program](getting-started.md), then [take the tour](tour.md).
- Continue with [tests](testing.md), [task recipes](common-tasks.md) and [Why Manuscript](why-manuscript.md).

## Find an API without leaving the terminal

In a POSIX terminal:

```sh
ms search_symbol PromiseOptions | head -n 2
```

```text
promise.PromiseOptions  record  std:@std/concurrency/promise.ms
  type PromiseOptions: timeout: Duration? = none cancel: Signal? = none
```

- Search includes project symbols and the bundled standard library.
- Give an agent `ms guide`; use `ms verify` for type, formatting, lint and test checks.

<span id="new-to-manuscript"></span>
<span id="ready-to-build"></span>
<span id="need-an-exact-answer"></span>
<span id="working-with-a-coding-agent"></span>

Next: [language reference](../core-language/_index.md), [API reference](../standard-library/reference/_index.md), [developer tools](../developer-tooling/_index.md).
