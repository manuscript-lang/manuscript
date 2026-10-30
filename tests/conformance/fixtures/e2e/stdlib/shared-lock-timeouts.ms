# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import {nanoseconds, milliseconds, sleep} from "@std/time.ms"

fn holder(box: Lock[Int], nap: Int) Int:
    var _g = box.lock()
    sleep(nanoseconds(nap))
    _g.close()
    return 0

fn waiter(box: Lock[Int]) Int:
    var g = box.lock()
    g.value = g.value + 1
    g.close()
    return 1

export fn main() Int:
    var served = 0

    for round in 0..60:
        let box = new_lock(0)
        let nap = 2000000 + round * 7000
        let g = TaskGroup[Int]()
        g.spawn(fn ch: holder(box, nap))
        sleep(nanoseconds(100000))

        let _first = g.spawn(
            fn ch: waiter(box),
            timeout: some(
                nanoseconds(nap - 100000 + (round % 7) * 3000 - 9000)
            )
        )
        let second = g.spawn(fn ch: waiter(box))
        if second.result().is_ok():
            served += 1

    let _ = stdout().write("served " + served.to_string() + "\n")
    return 0
