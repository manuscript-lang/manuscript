// conform: tags=scope-cleanup,interfaces,tier-io
// conform: phase=run
// conform: origin=close-matrix
import Closeable from "@std/core.ms"

// A temporary passed to a `Closeable` interface parameter is a resource the interface value owns:
// the call borrows it and the statement end closes it once, however the call ends.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")
        return ok(unit)

fn fails() Int!:
    return error(Error("later argument"))

fn look(c: Closeable) Unit:
    return

fn look_later(c: Closeable, n: Int) Unit:
    return

fn attempt() Unit!:
    look(Door("direct"))
    look_later(Door("later"), try fails())
    return ok(unit)

fn main() Unit:
    let _ = attempt()
    print("end")
