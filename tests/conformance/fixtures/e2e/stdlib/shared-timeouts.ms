# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

# A task cancelled while it waits its turn leaves the queue, so the next waiter is still served.

fn nap_holding(var value: Int, nap: Int) Unit:
    sleep(nanoseconds(nap))

fn holder(var box: Shared[Int], nap: Int) Int:
    nap_holding(var box, nap)
    return 0

fn waiter(var box: Shared[Int]) Int:
    let seen: Int = box
    box = seen + 1
    return 1

export fn main() Int:
    var served = 0

    for round in 0..60:
        var box = Shared(0)
        let nap = 2000000 + round * 7000
        let g = TaskGroup[Int]()
        var held = box
        g.spawn(fn ch: holder(var held, nap))
        sleep(nanoseconds(100000))

        var early = box
        let _first = g.spawn(
            fn ch: waiter(var early),
            timeout: nanoseconds(nap - 100000 + (round % 7) * 3000 - 9000)
        )
        var late = box
        let second = g.spawn(fn ch: waiter(var late))
        if second.result().is_ok():
            served += 1

    let _ = stdout().write("served " + served.to_string() + "\n")
    return 0
