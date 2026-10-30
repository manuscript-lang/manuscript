import Closeable from "@std/core.ms"
import {new_lock, Lock} from "@std/lock.ms"
import expect_equal from "@std/test.ms"

type Door:
    id: Int
    log: Lock[List[Int]]

impl Closeable for Door:
    var fn close() Unit:
        var seen = self.log.lock()
        seen.value.append(self.id)

fn keep_if(d: Door, keep: Bool) Optional[Door]:
    if keep:
        return some(d)

    return none

test "a parameter the callee drops on some path is closed there":
    let log: Lock[List[Int]] = new_lock([])
    let kept = keep_if(Door(1, log), true)
    log.get().clone() | try expect_equal([])

    let dropped = keep_if(Door(2, log), false)
    log.get().clone() | try expect_equal([2])
    if kept.is_some() and dropped.is_none():
        log.get().clone() | try expect_equal([2])

test "a bound resource passed to such a callee closes once":
    let log: Lock[List[Int]] = new_lock([])
    let door = Door(3, log)
    let dropped = keep_if(door, false)
    log.get().clone() | try expect_equal([3])
    if dropped.is_none():
        log.get().clone() | try expect_equal([3])
