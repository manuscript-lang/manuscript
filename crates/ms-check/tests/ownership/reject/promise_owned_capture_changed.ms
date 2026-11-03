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
    let p = promise(fn:  // error: this promise owns `door` and cannot change it
        door.knock()
        return ok(1)
    )
    return p.wait()
