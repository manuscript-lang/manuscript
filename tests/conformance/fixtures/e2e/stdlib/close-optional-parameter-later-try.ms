// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=close-matrix
import Closeable from "@std/core.ms"

// A temporary converted to an `Optional` parameter stays owned while a later argument's `try` fails:
// the resource closes once on that error path.
type Door:
    name: String

fn var Door.close() Void!:
    print("closed {self.name}")

fn fails() Int!:
    return error(Error("later argument"))

fn take(door: Door?, n: Int) Void:
    return

fn attempt() Void!:
    take(Door("temp"), fails()?)

fn main() Void:
    void attempt()
    print("end")
