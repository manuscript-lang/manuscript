import promise from "@std/concurrency/promise.ms"

fn run() Int:
    var xs = [1, 2]
    ps := [1, 2].map(fn i: promise[Int](fn: ok(xs.length() + i)))
    xs.append(3)  // error: cannot change `xs` while promise `ps`
    return ps.length()
