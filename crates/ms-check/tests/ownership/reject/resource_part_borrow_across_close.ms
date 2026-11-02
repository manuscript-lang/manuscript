import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit!:
        return ok(unit)

# A value derived from a resource cannot be used once the resource is closed.
fn main() Unit:
    var r = Res("a")
    let n = r.name
    let _ = r.close()  # error: cannot change `r` while `n` borrows it
    let _ = n.length()
