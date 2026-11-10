// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import Closeable from "@std/core.ms"
import promise from "@std/concurrency/promise.ms"

type Door:
    names: List[String]

impl Closeable for Door:
    var fn close() Unit!:
        print("closed")
        return ok(unit)

impl Door:
    var fn swing() Int:
        self.names.append("swung")
        return self.names.length()

fn use(var door: Door) Int!:
    return ok(door.swing())

// A promise that passes a captured `var` resource on owns it from the capture: it closes the door once
// when its work ends and drops its names (`make leak-check` reports a block left behind).
export fn main() Int:
    var door = Door(["front", "back"])
    moved := promise(fn: use(var door))
    print("{moved.wait().get(0)}")
    return 0
