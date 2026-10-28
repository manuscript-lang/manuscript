import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit:
        return unit

type Holder:
    items: List[Res]

# A copy of a resource would be closed a second time.
fn main() Int:
    let r = Res("a")
    let copy = r.clone()  # error: cannot be cloned
    let h = Holder([Res("b")])
    let again = h.clone()  # error: cannot be cloned
    return (
        copy.name.length()
        + again.items.length()
        + h.items.length()
        + r.name.length()
    )
