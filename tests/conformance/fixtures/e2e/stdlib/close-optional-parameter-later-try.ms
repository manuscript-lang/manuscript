// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=close-matrix
import Closeable from "@std/core.ms"

// A temporary converted to an `Optional` parameter stays owned while a later argument's `try` fails:
// the resource closes once on that error path.
type Door:
    name: String

fn var Door.close() Unit!:
    print("closed {self.name}")

fn fails() Int!:
    return error(Error("later argument"))

fn take(door: Door?, n: Int) Unit:
    return

fn attempt() Unit!:
    take(Door("temp"), fails()?)

fn main() Unit:
    _ := attempt()
    print("end")
