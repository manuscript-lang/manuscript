+++
title = "Evaluation order and call preparation"
weight = 95
+++

# Evaluation order and call preparation

Observe written argument order; save as `order.ms`.

<!-- manuscript-example: {"mode":"run","filename":"order.ms","stdout":"2\n1\n12\n"} -->
```manuscript
fn mark(value: Int) Int:
    print(value)
    return value

fn combine(first: Int, second: Int) Int:
    return first * 10 + second

export fn main() Int:
    print(combine(second: mark(2), first: mark(1)))
    return 0
```

```sh
ms run order.ms
```

```text
2
1
12
```

- Evaluate arguments left to right before mapping them to parameters.
- Alpha: lowering internals may change.


Next: [source call rules](../../../core-language/functions/declarations-and-calls.md) and [cleanup](cleanup-and-faults.md).
