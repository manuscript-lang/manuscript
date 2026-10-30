# conform: tags=scope-cleanup,records,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io.ms"
import Closeable from "@std/core.ms"

# A resource with only scalar fields has no storage to free, but a temporary of it is still closed.
type Counter:
    id: Int

impl Closeable for Counter:
    var fn close() Unit:
        stdout().write("closed {self.id}\n").get()

impl Counter:
    fn value() Int:
        return self.id

fn open_counter(id: Int) Counter:
    return Counter(id)

export fn main() Int:
    let a = open_counter(7).value()
    stdout().write("read {a}\n").get()
    return 0
