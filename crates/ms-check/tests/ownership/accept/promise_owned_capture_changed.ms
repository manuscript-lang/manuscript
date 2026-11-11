import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"

type Door:
    count: Int

fn var Door.close() Unit!:
    return ok(unit)

fn var Door.knock() Unit:
    self.count += 1

fn f() Int!:
    var door = Door(count: 0)
    p := promise(fn:
        door.knock()
        return ok(1)
    )
    return p.wait()
