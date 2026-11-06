// Scheduler mailbox traffic: starts N short promise tasks from the main thread, in rounds, and waits
// for each. Every promise is a Start sent to a scheduler thread and an Ended event sent back, so the
// run is dominated by cross-thread mail. `ms run bench/perf/mailbox/main.ms -- 200000 5`.
import promise, Promise from "@std/concurrency/promise.ms"
import arguments from "@std/os/env.ms"
import monotonic_time from "@std/os/system.ms"

fn work(a: Int) Int!:
    return ok(a * 2 + 1)

export fn main() Int:
    let args = arguments()
    let n = args[0].parse_int().get()
    let rounds = args[1].parse_int().get()
    var total = 0
    let t0 = monotonic_time()

    for r in 0..rounds:
        var promises: List[Promise[Int]] = []
        for i in 0..n:
            promises.append(promise[Int](fn: work(i)))
        for p in promises:
            total = total + p.wait().get()

    let t1 = monotonic_time()
    print("total " + total.to_string())
    print("ns/promise " + ((t1 - t0) / (n * rounds)).to_string())
    return 0
