import Promise, promise, wait_all from "@std/concurrency/promise.ms"
import monotonic from "@std/time.ms"

fn fib(n: Int) Int:
    if n < 2:
        return n

    return fib(n - 1) + fib(n - 2)

export fn main() Int:
    let start = monotonic()
    var tasks = List[Promise[Int]]()
    for _i in 0..4:
        tasks.append(promise(fn: ok(fib(36))))

    let results = wait_all(tasks).get(List[Int]())
    let parallel = monotonic().difference(start).nanos / 1000000
    let again = monotonic()
    var total = 0
    for _i in 0..4:
        total += fib(36)

    let serial = monotonic().difference(again).nanos / 1000000
    if total == 0:
        return 1

    print("{results.length()} tasks: {parallel} ms in parallel, {serial} ms one by one")
    return 0
