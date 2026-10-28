from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

# The list closes its elements, so a value borrowed from one cannot outlive a change to the list.
def main() -> Unit:
    var rs = [Res("a")]
    let n = rs[0].name
    rs.append(Res("b"))  # error: cannot change `rs` while `n` borrows it

    let _ = n.length()
