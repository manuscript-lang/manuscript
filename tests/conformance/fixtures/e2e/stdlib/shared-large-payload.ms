# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
import stdout from "@std/io/io.ms"
import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"

# A write through the handle changes the payload in place, so it costs the same for a large
# payload, and a group of many tasks (whose registry is a shared list) stays linear.
# Copying the payload on every change made this program take minutes.

export fn main() Int:
    var big = List[Int]()
    for i in 0..200000:
        big.append(i)

    var box: Shared[List[Int]] = Shared(big)

    for round in 0..3000:
        box[0] = round

    stdout().write("first {box[0]} length {box.length()}\n").get()

    var group = TaskGroup[Int]()
    for i in 0..20000:
        group.spawn(fn ch: i)

    let results = group.results().get([])
    stdout().write("tasks {results.length()} last {results[19999]}\n").get()
    group.close().get(none)
    return 0
