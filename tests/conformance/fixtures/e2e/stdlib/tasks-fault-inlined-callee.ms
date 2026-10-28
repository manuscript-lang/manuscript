# conform: tags=faults,stdlib-tasks,tier-io
# conform: phase=run
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds, sleep

# The callee inlines `sleep` (from another file) before it faults: the trace must still name this
# file for the closure frame, not the file of the first inlined callee.

def boom() -> Int:
    sleep(nanoseconds(1000000))

    let xs = [1]
    return xs[5]

export def main() -> Int:
    var group = TaskGroup[Int]()
    group.spawn(lambda ch: boom())

    let _ = group.results()
    group.close()
    return 0
