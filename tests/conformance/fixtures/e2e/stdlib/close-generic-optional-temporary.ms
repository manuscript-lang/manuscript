// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=bug-bash-generics
import Closeable from "@std/core.ms"

// A generic function that returns its parameter as an optional hands a temporary argument to the
// caller: the resource closes once, with the binding.
type Door:
    name: String

fn var Door.close() Void!:
    print("closed {self.name}")

fn opt[T](v: T) T?: v

fn main() Void:
    _a := opt(Door("temp"))
    print("end")
