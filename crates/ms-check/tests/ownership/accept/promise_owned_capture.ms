import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"

type Door:
    count: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

fn size(door: Door) Int!:
    return ok(door.count)

fn f() Int!:
    let door = Door(count: 1)
    let p = promise(fn: size(door))
    return p.wait()
