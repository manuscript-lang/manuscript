# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import nanoseconds, sleep from "@std/time.ms"

fn bump(box: Shared[Int], n: Int) Int:
    for i in 0..50:
        var g = lock(box)
        g.value = g.value + 1
        sleep(nanoseconds(20000))

    return n

export fn main() Int:
    let box = share(0)
    var g = TaskGroup[Int]()

    for n in 0..100:
        let b = box
        g.spawn(fn ch: bump(b, n))

    let _ = g.results()
    g.close()

    let _ = stdout().write("total " + box.get().to_string() + "\n")
    return 0
