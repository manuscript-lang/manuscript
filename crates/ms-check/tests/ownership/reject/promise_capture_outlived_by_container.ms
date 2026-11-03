import promise, Promise from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn f() Int!:
    var running: List[Promise[Int]] = []
    for i in 0..2:
        var mine: List[Int] = []
        mine.append(i)
        running.append(promise(fn: total(mine)))  // error: this promise reads `mine`, which ends before `running` does
    return ok(running.length())
