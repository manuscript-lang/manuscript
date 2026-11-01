import Closeable from "@std/core.ms"
import Shared from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

type Door:
    id: Int
    log: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit!:
        self.log.append(self.id)
        return ok(unit)

fn keep_if(d: Door, keep: Bool) Door?:
    if keep:
        return d

    return none

test "a parameter the callee drops on some path is closed there":
    let log: Shared[List[Int]] = Shared([])
    let kept = keep_if(Door(1, log), true)
    log.clone() | try expect_equal([])

    let dropped = keep_if(Door(2, log), false)
    log.clone() | try expect_equal([2])
    if kept.is_some() and dropped.is_none():
        log.clone() | try expect_equal([2])

test "a bound resource passed to such a callee closes once":
    let log: Shared[List[Int]] = Shared([])
    let door = Door(3, log)
    let dropped = keep_if(door, false)
    log.clone() | try expect_equal([3])
    if dropped.is_none():
        log.clone() | try expect_equal([3])
