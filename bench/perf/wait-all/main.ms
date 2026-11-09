import Promise, promise, wait_all from "@std/concurrency/promise.ms"
import sleep, milliseconds from "@std/time.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

fn work(i: Int, jitter: Bool) Int!:
    if jitter:
        try sleep(milliseconds(i % 5)).wait()
    return ok(i)

// The list-order implementation before #2915, retained only as a performance control.
// Unlike wait_all it does not report a later input's error promptly.
fn ordered_wait_all[T](promises: List[Promise[T]]) List[T]!:
    var pending = promises
    var results: List[T] = []
    for index in 0..pending.length():
        results.append(try pending[index].wait())
    return ok(results)

export fn main() Int:
    let args = arguments()
    let count = args[0].parse_int().get()
    let jitter = args[1] == "jitter"
    let before = monotonic()
    var promises: List[Promise[Int]] = []
    for i in 0..count:
        promises.append(promise[Int](fn: work(i, jitter)))

    let spawned = monotonic()
    let results = if args.length() > 2 and args[2] == "ordered": ordered_wait_all(
        promises
    ).get() else: wait_all(promises).get()
    var total = 0
    var at = 0

    for result in results:
        if result != at:
            return 3

        at += 1
        total += result

    if at != count:
        return 4

    print("count " + at.to_string() + " checksum " + total.to_string())
    print("spawn_ns " + spawned.difference(before).to_nanoseconds().to_string())
    print("total_ns " + monotonic().difference(before).to_nanoseconds().to_string())
    return 0
