// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import Closeable from "@std/core.ms"
import promise from "@std/concurrency/promise.ms"

type Door:
    names List[String]

fn move Door.close() Void!:
    print("closed")

fn var Door.swing() Int:
    self.names.append("swung")
    return self.names.length()

fn use(var door Door) Int!:
    return ok(door.swing())

// A promise waited in the function borrows its captures, so the `var` door stays `main`'s: it closes once
// when `main` ends and drops its names (`make leak-check` reports a block left behind).
fn main() Void:
    var door = Door(["front", "back"])
    moved := promise(() => use(door))
    print(f"{moved.wait().get_or(0)}")
