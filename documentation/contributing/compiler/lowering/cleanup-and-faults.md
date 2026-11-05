+++
title = "Cleanup and fault lowering"
weight = 96
+++

# Cleanup and fault lowering

Observe reverse-order resource release; save as `cleanup.ms`.

<!-- manuscript-example: {"mode":"run","filename":"cleanup.ms","stdout":"using first and second\nclosed second\nclosed first\n"} -->
```manuscript
import Closeable from "@std/core.ms"

type Resource:
    name: String
    closed: Bool = false

impl Closeable for Resource:
    var fn close() Unit!:
        if self.closed:
            return ok(unit)
        self.closed = true
        print("closed {self.name}")
        return ok(unit)

export fn main() Int:
    let first = Resource("first")
    let second = Resource("second")
    print("using {first.name} and {second.name}")
    return 0
```

```sh
ms run cleanup.ms
```

```text
using first and second
closed second
closed first
```

- Repeated close calls must not release the resource twice.
- Alpha: cleanup lowering may change.


Next: [exit order](../../../core-language/cleanup/exit-order.md), [cleanup faults](../../../core-language/cleanup/cleanup-faults.md), and [lowering code](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-lower/src/close.rs).
