import promise from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn f() Int!:
    var xs = [1, 2, 3]
    p := promise(fn: total(xs))
    xs.append(4)  // error: while promise `p` (started at 8:10) reads it
    return p.wait()
