import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit:
        return unit

# The list closes its elements, so a value borrowed from one cannot outlive a change to the list.
fn main() Unit:
    var rs = [Res("a")]
    let n = rs[0].name
    rs.append(Res("b"))  # error: cannot change `rs` while `n` borrows it

    let _ = n.length()
