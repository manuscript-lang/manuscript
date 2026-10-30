# conform: tags=scope-cleanup,faults,stdlib-tasks,tier-io
# conform: phase=run
import Closeable from "@std/core.ms"
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"
import nanoseconds, sleep from "@std/time.ms"

type Bad:
    tag: Int

impl Closeable for Bad:
    var fn close() Unit:
        stdout().write("cleanup faulting\n").get()

        let xs = List[Int]()
        stdout().write("{xs[3]}\n").get()

fn work() Int:
    let _b = Bad(1)
    sleep(nanoseconds(5000000000))
    return 1

export fn main() Int:
    var group = TaskGroup[Int](timeout: some(nanoseconds(50000000)))
    group.spawn(fn ch: work())

    let _ = group.wait()
    group.close()
    return 0
