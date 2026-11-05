+++
title = "Scope and capture checking"
weight = 90
+++

# Scope and closure checking

Expose a callback’s captured value; save as `capture.ms`.

<!-- manuscript-example: {"mode":"run","filename":"capture.ms","stdout":"12\n"} -->
```manuscript
export fn main() Int:
    let offset = 2
    let adjust = fn(value: Int) Int:
        return value + offset
    print(adjust(10))
    return 0
```

```sh
ms run capture.ms
```

```text
12
```

- Non-escaping closures borrow captures; escaping closures own them.
- Alpha: capture rules may evolve.


Next: [closure rules](../../../core-language/functions/function-values-and-closures.md) and [ownership checks](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).
