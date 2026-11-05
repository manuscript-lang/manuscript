+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

Observe cleanup order by printing when each resource closes. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"run","filename":"example.ms","stdout":"work\nclose second\nclose first\n"} -->
```manuscript {filename="example.ms"}
import Closeable from "@std/core.ms"

type Tracked:
    name: String
    closed: Bool = false

impl Closeable for Tracked:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            print("close {self.name}")
        return ok(unit)

fn work() Unit!:
    let _first = Tracked("first")
    let _second = Tracked("second")
    print("work")
    return ok(unit)

export fn main() Int:
    if let _done = work():
        return 0
    return 1
```

```sh
ms run example.ms
```

```text
work
close second
close first
```

<a id="observe-the-order"></a>

- Return expressions evaluate before cleanup: inner scopes first, then newest bindings. Owned parts close in reverse order.
- Returning or capturing in an escaping closure moves ownership; borrowing adds no cleanup.

Next: [owned parts](closeable.md#records-and-collections-close-what-they-hold) and [cleanup failures](cleanup-faults.md).
