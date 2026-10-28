from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

type Holder:
    items: List[Res]

# A copy of a resource would be closed a second time.
def main() -> Int:
    let r = Res("a")
    let copy = r.clone()  # error: cannot be cloned
    let h = Holder([Res("b")])
    let again = h.clone()  # error: cannot be cloned
    return copy.name.length() + again.items.length() + h.items.length() + r.name.length()
