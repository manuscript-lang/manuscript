import promise, Promise from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn f() Int!:
    let shared = [1, 2, 3]
    var running: List[Promise[Int]] = []
    for i in 0..2:
        running.append(promise(fn: total(shared)))
    return ok(running.length())
