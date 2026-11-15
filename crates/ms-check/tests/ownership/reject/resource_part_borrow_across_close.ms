import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Void!:
    return ok(unit)

// A value derived from a resource cannot be used once the resource is closed.
fn main() Void:
    var r = Res("a")
    n := r.name
    _ := r.close()  // error: cannot change `r` while `n` borrows it
    _ := n.length()
