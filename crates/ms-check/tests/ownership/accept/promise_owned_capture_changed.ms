import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"

type Door:
    count: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

impl Door:
    var fn knock() Unit:
        self.count += 1

fn f() Int!:
    var door = Door(count: 0)
    p := promise(fn:
        door.knock()
        return ok(1)
    )
    return p.wait()
