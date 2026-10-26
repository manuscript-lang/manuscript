# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
from "@std/io.ms" import stdout
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup

# Closing a guard hands the payload back without copying it, so locking costs the same for a large
# payload, and a group of many tasks (whose registry is a locked list) stays linear.
# Copying the payload on every lock made this program take minutes.

export def main() -> Int:
    var big = List[Int]()
    for i in 0..200000:
        big.append(i)
    let box: Shared[List[Int]] = share(big)
    for round in 0..3000:
        with var guard = lock(box):
            guard.value[0] = round
    stdout().write(f"first {box.get()[0]} length {box.get().length()}\n").get()

    with let group = TaskGroup[Int]():
        for i in 0..20000:
            group.spawn(lambda ch: i)
        let results = group.results().get([])
        stdout().write(f"tasks {results.length()} last {results[19999]}\n").get()
    return 0
