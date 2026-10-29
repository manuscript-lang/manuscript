# conform: tags=faults,stdlib-tasks,tier-io
# conform: phase=run
import TaskGroup from "@std/tasks.ms"
import {nanoseconds, sleep} from "@std/time.ms"

# The callee inlines `sleep` (from another file) before it faults: the trace must still name this
# file for the closure frame, not the file of the first inlined callee.

fn boom() Int:
    sleep(nanoseconds(1000000))

    let xs = [1]
    return xs[5]

export fn main() Int:
    var group = TaskGroup[Int]()
    group.spawn(fn ch: boom())

    let _ = group.results()
    group.close()
    return 0
