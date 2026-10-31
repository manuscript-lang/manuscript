import Closeable from "@std/core.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"
import expect_equal from "@std/test.ms"

type Door:
    id: Int
    log: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit:
        var seen = lock(self.log)
        seen.value.append(self.id)

fn keep_if(d: Door, keep: Bool) Door?:
    if keep:
        return d

    return none

test "a parameter the callee drops on some path is closed there":
    let log: Shared[List[Int]] = share([])
    let kept = keep_if(Door(1, log), true)
    log.get().clone() | try expect_equal([])

    let dropped = keep_if(Door(2, log), false)
    log.get().clone() | try expect_equal([2])
    if kept.is_some() and dropped.is_none():
        log.get().clone() | try expect_equal([2])

test "a bound resource passed to such a callee closes once":
    let log: Shared[List[Int]] = share([])
    let door = Door(3, log)
    let dropped = keep_if(door, false)
    log.get().clone() | try expect_equal([3])
    if dropped.is_none():
        log.get().clone() | try expect_equal([3])
