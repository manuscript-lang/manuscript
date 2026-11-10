import promise from "@std/concurrency/promise.ms"

fn run() Int:
    var xs = [1, 2]
    p := promise[Int](fn: ok(xs.length()))
    q := promise[Int](fn: ok(xs.length()))
    all := [p, q]
    xs.append(3)  // error: cannot change `xs` while promise `all`
    return all.length()
