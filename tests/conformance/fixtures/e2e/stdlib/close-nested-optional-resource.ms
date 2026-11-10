// conform: tags=scope-cleanup,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// An optional nested in an optional still owns the resource inside it.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")
        return ok(unit)

fn nested(n: String) Door??:
    inner: Door? = Door(n)
    return inner

export fn main() Int:
    bound := nested("bound")
    present := nested("temporary").is_some()
    print("end {bound.is_some()} {present}")
    return 0
