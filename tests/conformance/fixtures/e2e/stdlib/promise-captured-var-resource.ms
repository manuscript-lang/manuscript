// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import Closeable from "@std/core.ms"
import promise from "@std/concurrency/promise.ms"

type Door:
    names: List[String]

fn var Door.close() Unit!:
    print("closed")

fn var Door.swing() Int:
    self.names.append("swung")
    return self.names.length()

fn use(var door: Door) Int!:
    return ok(door.swing())

// A promise that passes a captured `var` resource on owns it from the capture: it closes the door once
// when its work ends and drops its names (`make leak-check` reports a block left behind).
fn main() Unit:
    var door = Door(["front", "back"])
    moved := promise(fn: use(var door))
    print("{moved.wait().get(0)}")
