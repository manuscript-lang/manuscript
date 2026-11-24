// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=bug-bash-generics
import Closeable from "@std/core.ms"

// A generic function that returns its parameter as an optional hands a temporary argument to the
// caller: the resource closes once, with the binding.
type Door:
    name String

fn move Door.close() Void!:
    print(f"closed {self.name}")

fn opt[T](move v T) T?: v

fn main() Void:
    _a := opt(Door("temp"))
    print("end")
