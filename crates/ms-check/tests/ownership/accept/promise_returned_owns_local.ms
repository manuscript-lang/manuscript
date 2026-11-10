import Promise, promise from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn start() Promise[Int]:
    xs := [1, 2, 3]
    return promise(fn: total(xs))
