import Closeable from "@std/core.ms"

type Res:
    name: String

fn move Res.close() Void!:
    return ok()

// A value derived from a resource cannot be used once the resource is closed.
fn main() Void:
    var r = Res("a")
    n := r.name
    void r.close()  // error: cannot move `r` while `n` borrows it
    void n.length()
