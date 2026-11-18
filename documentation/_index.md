+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "A statically typed, natively compiled language with single ownership and no garbage collector. Diagnostics name the cause and the fix."
+++

{{< docs-home part="hero" >}}

## A taste

<div class="home-taste">

Using a value after it moved is a compile error:

<!-- manuscript-example: {"mode":"error","contains":"is moved here"} -->
```rust
fn main() Void:
    var names = List[String]()
    first := "ada"
    names.append(first)
    print(first)
    // type: `first` is moved here but used again at 5:11
```

Promises run across all cores. There is no `async` or `await`:

```rust
import promise, wait_all from "@std/concurrency/promise.ms"

fn fib(n: Int) Int:
    return if n < 2: n else: fib(n - 1) + fib(n - 2)

fn main() Void:
    tasks := [36, 36, 36, 36].map(fn n: promise(fn: ok(fib(n))))
    print(wait_all(tasks).get_or(List[Int]()).length())
```

</div>

![A screencast of Manuscript: failure as values, ownership errors, promises, ms verify, the call graph and a native build, each with a short caption.](/images/screencast.gif "A short tour: errors, ownership, promises, ms verify, the call graph and a native build.")

{{< docs-home part="paths" >}}

{{< docs-home part="proof" >}}
