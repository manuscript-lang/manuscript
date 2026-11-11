import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Unit!:
    return ok(unit)

type Holder:
    items: List[Res]

// A copy of a resource would be closed a second time.
fn main() Int:
    r := Res("a")
    copy := r.clone()  // error: cannot be cloned
    h := Holder([Res("b")])
    again := h.clone()  // error: cannot be cloned
    return (
        copy.name.length()
        + again.items.length()
        + h.items.length()
        + r.name.length()
    )
