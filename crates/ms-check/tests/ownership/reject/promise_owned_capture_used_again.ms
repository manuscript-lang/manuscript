import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"

type Door:
    count: Int

fn var Door.close() Unit!:
    return ok(unit)

fn size(door: Door) Int!:
    return ok(door.count)

fn f() Int!:
    door := Door(count: 1)
    p := promise(fn: size(door))  // error: this closure outlives the statement, so it takes `door` with it
    again := size(door)
    return p.wait()
