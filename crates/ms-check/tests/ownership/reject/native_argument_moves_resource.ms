import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn demo() Int:
    cause := Marker(1)
    missing: Int? = none
    kept := missing.ok_or(cause)  // error: `cause` is moved here but used again at 13:12; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read
    return cause.id
