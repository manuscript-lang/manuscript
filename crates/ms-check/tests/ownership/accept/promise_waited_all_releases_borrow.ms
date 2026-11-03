import promise, wait_all from "@std/concurrency/promise.ms"

fn run() Int!:
    var xs = [1, 2]
    let p = promise[Int](fn: ok(xs.length()))
    let q = promise[Int](fn: ok(xs.length()))
    let all = try wait_all([p, q])
    xs.append(3)
    return ok(all.length() + xs.length())
