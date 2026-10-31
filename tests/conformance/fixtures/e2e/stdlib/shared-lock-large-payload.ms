# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"

# Closing a guard hands the payload back without copying it, so locking costs the same for a large
# payload, and a group of many tasks (whose registry is a locked list) stays linear.
# Copying the payload on every lock made this program take minutes.

export fn main() Int:
    var big = List[Int]()
    for i in 0..200000:
        big.append(i)

    let box: Shared[List[Int]] = share(big)

    for round in 0..3000:
        var guard = lock(box)
        guard.value[0] = round

    stdout().write("first {box.get()[0]} length {box.get().length()}\n").get()

    var group = TaskGroup[Int]()
    for i in 0..20000:
        group.spawn(fn ch: i)

    let results = group.results().get([])
    stdout().write("tasks {results.length()} last {results[19999]}\n").get()
    group.close().get(none)
    return 0
