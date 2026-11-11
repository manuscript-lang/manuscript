// conform: tags=scope-cleanup,records,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A resource with only scalar fields has no storage to free, but a temporary of it is still closed.
type Counter:
    id: Int

fn var Counter.close() Unit!:
    print("closed {self.id}")

fn Counter.value() Int:
    return self.id

fn open_counter(id: Int) Counter:
    return Counter(id)

fn main() Unit:
    a := open_counter(7).value()
    print("read {a}")
