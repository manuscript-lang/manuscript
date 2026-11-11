import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Unit!:
    return ok(unit)

// The list closes its elements, so a value borrowed from one cannot outlive a change to the list.
fn main() Unit:
    var rs = [Res("a")]
    n := rs[0].name
    rs.append(Res("b"))  // error: cannot change `rs` while `n` borrows it

    _ := n.length()
