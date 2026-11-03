import Promise, promise from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn start() Promise[Int]:
    let xs = [1, 2, 3]
    let p = promise(fn: total(xs))
    return p  # error: this promise reads `xs`, which ends with this function
