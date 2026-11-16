import promise from "@std/concurrency/promise.ms"

fn run() Int:
    var xs = [1, 2]
    ps := [1, 2].map(fn i: promise[Int](fn: ok(xs.length() + i)))  // error: capture `xs.clone()`
    return ps.length() + xs.length()
