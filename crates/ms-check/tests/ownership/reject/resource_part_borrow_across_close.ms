import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Void!:
    return ok(void)

// A value derived from a resource cannot be used once the resource is closed.
fn main() Void:
    var r = Res("a")
    n := r.name
    void r.close()  // error: cannot change `r` while `n` borrows it
    void n.length()
