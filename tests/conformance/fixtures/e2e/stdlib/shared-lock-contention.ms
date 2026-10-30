# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn bump(box: Lock[Int], n: Int) Int:
    for i in 0..50:
        var g = box.lock()
        g.value = g.value + 1
        sleep(nanoseconds(20000))

    return n

export fn main() Int:
    let box = new_lock(0)
    var g = TaskGroup[Int]()

    for n in 0..100:
        let b = box
        g.spawn(fn ch: bump(b, n))

    let _ = g.results()
    g.close()

    let _ = stdout().write("total " + box.get().to_string() + "\n")
    return 0
