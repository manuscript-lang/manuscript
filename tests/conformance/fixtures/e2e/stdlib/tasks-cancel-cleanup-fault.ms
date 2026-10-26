# conform: tags=with-cleanup,faults,stdlib-tasks,tier-io
# conform: phase=run
from "@std/core.ms" import Closeable
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds, sleep

type Bad:
    tag: Int

impl Closeable for Bad:
    var def close() -> Unit:
        stdout().write("cleanup faulting\n").get()
        let xs = List[Int]()
        stdout().write(f"{xs[3]}\n").get()

def work() -> Int:
    with let b = Bad(1):
        sleep(nanoseconds(5000000000))
        return 1

export def main() -> Int:
    with let group = TaskGroup[Int](timeout: some(nanoseconds(50000000))):
        group.spawn(lambda ch: work())
        group.wait()
    return 0
