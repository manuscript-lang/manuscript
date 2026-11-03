import promise from "@std/concurrency/promise.ms"

fn run() Int:
    var xs = [1, 2]
    let ps = [1, 2].map(fn i:
        let q = promise[Int](fn: ok(xs.length() + i))
        return q
    )
    xs.append(3)  // error: cannot change `xs` while promise `ps`
    return ps.length()
