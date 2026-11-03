import promise from "@std/concurrency/promise.ms"

fn run() Int:
    var xs = [1, 2]
    let p = promise[Int](fn: ok(xs.length()))
    let q = promise[Int](fn: ok(xs.length()))
    let all = [p, q]
    xs.append(3)  // error: cannot change `xs` while promise `all`
    return all.length()
