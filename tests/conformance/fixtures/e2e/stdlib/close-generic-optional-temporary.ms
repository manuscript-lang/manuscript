// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=bug-bash-generics
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

// A generic function that returns its parameter as an optional hands a temporary argument to the
// caller: the resource closes once, with the binding.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

fn opt[T](v: T) T?: v

export fn main() Int:
    let _a = opt(Door("temp"))
    stdout().write("end\n").get()
    return 0
