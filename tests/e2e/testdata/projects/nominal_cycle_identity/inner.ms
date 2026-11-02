import Closeable from "@std/core.ms"
import Shared from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"

export type Door:
    log: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit!:
        var seen = lock(self.log)
        seen.value.append(1)
        return ok(unit)

export type Node:
    door: Door

export fn make_inner(log: Shared[List[Int]]) Node:
    return Node(Door(log))
