# expect-stdout: close one
# expect-stdout: close two
# expect-stdout: waited: true
# A guarded task faults after moving a resource field: the cleanup stack closes the moved door through its new owner and the other one through the record, once each.
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

type Room:
    first: Door
    second: Door

fn faulting() Unit:
    let r = Room(Door("one"), Door("two"))
    var xs: List[Door] = []
    xs.append(r.first)
    panic("fault after the move")

export fn main() Int:
    let group = TaskGroup[Unit](contain_faults: true)
    group.spawn(fn ch: faulting())

    let waited = group.wait()
    stdout().write("waited: {waited.is_error()}\n").get()
    return 0
