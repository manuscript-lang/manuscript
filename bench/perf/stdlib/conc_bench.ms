import (
    keep, measure from "@std/test/bench.ms",
    Promise, promise, wait_all from "@std/concurrency/promise.ms",
)

bench "promise.spawn_wait_all_1000":
    fn work() Result[Unit, Error]:
        var running: List[Promise[Int]] = []
        for i in 0..1000:
            running.append(promise(fn: ok(i * 2)))

        r := wait_all(running).get([])
        return keep(r.length())

    try measure(1000, work)

bench "promise.spawn_wait_each_1000":
    fn work() Result[Unit, Error]:
        var n = 0

        for i in 0..1000:
            p := promise(fn: ok(i * 2))
            n += p.wait().get(0)

        return keep(n)

    try measure(1000, work)

bench "promise.spawn_then_wait_5000":
    fn work() Result[Unit, Error]:
        var running: List[Promise[Int]] = []
        for i in 0..5000:
            running.append(promise(fn: ok(i)))

        var n = 0
        for v in wait_all(running).get([]):
            n += v
        return keep(n)

    try measure(5000, work)
