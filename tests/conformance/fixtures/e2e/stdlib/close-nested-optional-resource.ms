# conform: tags=scope-cleanup,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io.ms"
import Closeable from "@std/core.ms"

# An optional nested in an optional still owns the resource inside it.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

fn nested(n: String) Door??:
    let inner: Door? = Door(n)
    return inner

export fn main() Int:
    let bound = nested("bound")
    let present = nested("temporary").is_some()
    stdout().write("end {bound.is_some()} {present}\n").get()
    return 0
