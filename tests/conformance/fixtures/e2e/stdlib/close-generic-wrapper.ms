# conform: tags=scope-cleanup,generics,records,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

# A generic wrapper closes the resource its instance holds; a plain instance closes nothing.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

type Wrap[T]:
    value: T

fn keep[T](v: T) Int:
    let _w = Wrap(v)
    return 0

fn keep_optional[T](v: T) Int:
    let _o: T? = v
    return 1

export fn main() Int:
    let a = keep(Door("wrapped"))
    let b = keep_optional(Door("optional"))
    let c = keep(5)
    stdout().write("end {a + b + c}\n").get()
    return 0
