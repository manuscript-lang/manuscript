# expect-stdout: close b
# expect-stdout: close a
# expect-stdout: waited: true
# A guarded task faults after moving one resource: the cleanup stack still closes the binding registered after it.
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"
import panic from "@std/core.ms"
import TaskGroup from "@std/concurrency/tasks.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("close {self.name}\n").get()
        return ok(unit)

fn faulting() Unit:
    var xs: List[Door] = []
    let a = Door("a")
    let b = Door("b")
    xs.append(a)

    let _n = b.name.length()
    panic("fault after the move")

export fn main() Int:
    var group = TaskGroup[Unit](contain_faults: true)
    group.spawn(fn var ch: faulting())

    let waited = group.wait()
    stdout().write("waited: {waited.is_error()}\n").get()
    return 0
