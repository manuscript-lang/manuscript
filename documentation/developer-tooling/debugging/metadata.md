+++
title = "Inspect checked source"
weight = 118
+++

# Inspect checked source

Follow checked declarations and call sites during review; save this as `hello.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n","filename":"hello.ms"} -->
```manuscript {filename="hello.ms"}
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

## Save a snapshot

```sh
ms run hello.ms
ms inspect hello.ms -o inspection.json
```

```text
Hello, Manuscript!
```

- Inspection succeeds silently and writes JSON without running or linking the program.
- Manuscript is in alpha; syntax, APIs and inspection formats may change.

Next: [inspection fields and byte spans](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-tooling/src/inspect.rs), [effects](../source/effects.md) and [native debugging](debugger-integration.md).

<span id="read-positions-and-identities"></span>
<span id="follow-a-running-program-instead"></span>
