import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit!:
        return ok(unit)

# fill, copy_within and merge store copies of what they are given.
fn main() Int:
    var xs = [Res("a"), Res("b")]
    xs.fill(Res("c"), 0, 2)  # error: fill requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    xs.copy_within(0, 1, 2)  # error: copy_within requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource

    var a = Map[String, Res]()
    var b = Map[String, Res]()
    a.merge(b)  # error: merge requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    return xs.length() + a.length()
