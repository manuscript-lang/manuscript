# conform: tags=scope-cleanup,faults,stdlib-tasks,tier-io
# conform: phase=run
import Closeable from "@std/core.ms"
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

type Bad:
    tag: Int

impl Closeable for Bad:
    var fn close() Unit!:
        stdout().write("cleanup faulting\n").get()

        let xs = List[Int]()
        stdout().write("{xs[3]}\n").get()
        return ok(unit)

fn work() Int:
    let _b = Bad(1)
    sleep(nanoseconds(5000000000))
    return 1

export fn main() Int:
    var group = TaskGroup[Int](timeout: nanoseconds(50000000))
    group.spawn(fn var ch: work())

    let _ = group.wait()
    group.close().get(none)
    return 0
