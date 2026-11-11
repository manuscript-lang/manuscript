import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Unit!:
    return ok(unit)

// A value derived from the `with` resource cannot be stored where it outlives the block.
fn main() Int:
    var kept = List[String]()
    var r = Res("b")
    n := r.name
    kept.append(n)  // error: cannot move `n` out: it is borrowed, not owned
    r.close().get(none)
    return kept.length()
