# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
from "@std/io.ms" import stdout
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds, sleep

def bump(box: Shared[Int], n: Int) -> Int:
    for i in 0..50:
        with var g = lock(box):
            g.value = g.value + 1
            sleep(nanoseconds(20000))

    return n

export def main() -> Int:
    let box = share(0)

    with let g = TaskGroup[Int]():
        for n in 0..100:
            let b = box
            g.spawn(lambda ch: bump(b, n))

        let _ = g.results()

    let _ = stdout().write("total " + box.get().to_string() + "\n")
    return 0
