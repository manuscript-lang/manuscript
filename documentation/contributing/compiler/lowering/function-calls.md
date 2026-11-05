+++
title = "Function lowering"
weight = 93
+++

# Function lowering

Distinguish callback creation from invocation; save as `calls.ms`.

<!-- manuscript-example: {"mode":"run","filename":"calls.ms","stdout":"created\ncallback\n12\n"} -->
```manuscript
fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

export fn main() Int:
    let offset = 2
    let adjust = fn(value: Int) Int:
        print("callback")
        return value + offset
    print("created")
    print(apply(10, adjust))
    return 0
```

```sh
ms run calls.ms
```

```text
created
callback
12
```

- Creating the closure does not execute its body.
- Alpha: closure layouts may change.


Next: [call preparation](evaluation-order.md) and [runtime ABI](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt/ABI.md).
