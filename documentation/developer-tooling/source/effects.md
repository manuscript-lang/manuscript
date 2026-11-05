+++
title = "Understanding effects"
weight = 3
+++

# Understanding effects

Review which calls can read, change data or reach external operations; save this as `hello.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n","filename":"hello.ms"} -->
```manuscript {filename="hello.ms"}
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

```sh
ms run hello.ms
ms diagram hello.ms --view effects --entity main
```

```text
Hello, Manuscript!
EFFECTS VIEW
`- main  effects: read+unknown
   `- @std/core.ms+source#fn#print
```

- `unknown` means unclassified behavior, not harmless behavior; follow the call path when reviewing it.
- Manuscript is in alpha; syntax, APIs and analysis output may change.

Next: [effect analysis rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/effects.rs), [cancellation](../../core-language/concurrency/promises.md#cancellation) and [code maps](../implementation.md#interactive-code-map).
