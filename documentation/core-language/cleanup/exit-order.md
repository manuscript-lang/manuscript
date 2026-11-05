+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

On scope exit, cleanup closes inner resources before outer ones, and the bindings of one scope last declared first. A borrow registers no extra close. A record or collection that owns resources closes its owned parts; see [holder cleanup](closeable.md#records-and-collections-close-what-they-hold).

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Call registered `close()` methods in reverse registration/nesting order.
3. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault can suppress a pending return or domain error; see [cleanup failures](cleanup-faults.md) for fault selection.

Returning an owned resource transfers its cleanup duty to the caller: the exiting scope does not close the moved value. Moving it into a field, collection or escaping closure likewise transfers responsibility to the new owner. A borrowed part cannot escape a local owner that is about to close; returning a borrow of an argument keeps the caller responsible for that owner.

## Observe the order

Save as `cleanup.ms` and run `ms run cleanup.ms`. The small resource below prints when it closes:

<!-- manuscript-example: {"mode":"run","stdout":"work\nclose second\nclose first\n"} -->
```manuscript
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

fn acquire(name: String) Tracked:
    return Tracked(name)

fn work() Unit!:
    let _first = acquire("first")
    let _second = acquire("second")
    print("work")
    return ok(unit)

export fn main() Int:
    let outcome = work()
    if let _completed = outcome:
        return 0
    print(outcome.err().message)
    return 1
```

```text
work
close second
close first
```

`acquire` returns the resource to `work`; it does not close it at the end of the factory. Ownership and the close duty move together. The return from `work` is prepared before either close, but `main` receives it only after both resources have closed. Change `work` to return an error after printing and the same close order still applies.

Declare dependencies in an outer scope, or before the resources that use them, so they close after the resources that use them. See [fault selection](cleanup-faults.md).
