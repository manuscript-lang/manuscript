import Closeable from "@std/core.ms"

type Res:
    name: String

type Holder:
    inner: Res
    all: List[Res]

fn var Res.close() Unit!:
    return ok(unit)

// Parts are closed at scope end; borrows of them used before then are fine.
fn held() Int:
    r := Res("c")
    n := r.name
    return n.length()

fn composite() Int:
    h := Holder(Res("a"), [Res("b")])
    n := h.inner.name
    m := h.all[0].name
    return n.length() + m.length()
