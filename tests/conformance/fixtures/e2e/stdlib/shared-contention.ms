# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

# Reads, waits, then writes: only one call at a time on the value keeps every update.
fn add_slowly(var total: Int) Unit:
    let seen = total
    sleep(nanoseconds(20000))
    total = seen + 1

fn bump(var box: Shared[Int], n: Int) Int:
    for i in 0..50:
        add_slowly(var box)
    return n

export fn main() Int:
    var box = Shared(0)
    var g = TaskGroup[Int]()

    for n in 0..100:
        var b = box
        g.spawn(fn var ch: bump(var b, n))

    let _ = g.results()
    g.close().get(none)

    let total: Int = box
    let _ = stdout().write("total " + total.to_string() + "\n")
    return 0
