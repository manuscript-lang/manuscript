# conform: tags=faults,stdlib-tasks,tier-io
# conform: phase=run
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import duration, sleep

# The callee inlines `sleep` (from another file) before it faults: the trace must still name this
# file for the closure frame, not the file of the first inlined callee.

def boom() -> Int:
    sleep(duration(1000000))
    let xs = [1]
    return xs[5]

export def main() -> Int:
    with let group = TaskGroup[Int]():
        group.spawn(lambda ch: boom())
        group.results()
    return 0
