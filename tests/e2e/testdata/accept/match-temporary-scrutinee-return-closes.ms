import Closeable from "@std/core.ms"
import Shared, share, lock from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

type Door:
    id: Int
    log: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit!:
        var seen = lock(self.log)
        seen.value.append(self.id)
        return ok(unit)

fn open(id: Int, log: Shared[List[Int]]) Door?:
    return Door(id, log)

fn early(log: Shared[List[Int]]) Int:
    match open(1, log):
        d:
            if d.id == 1:
                return 10

            return 20
        none:
            return 0

fn late(log: Shared[List[Int]]) Int:
    let n = match open(2, log):
        d: d.id
        none: 0

    return n

fn hand_on(log: Shared[List[Int]]) Door?:
    match open(3, log):
        d: return d
        none: return none

test "a payload moved out of the arm is not closed by the match":
    let log: Shared[List[Int]] = share([])
    let kept = hand_on(log)
    log.get().clone() | try expect_equal([])
    if kept.is_some():
        log.get().clone() | try expect_equal([])

test "return from an arm closes the temporary scrutinee once":
    let log: Shared[List[Int]] = share([])
    early(log) | try expect_equal(10)
    log.get().clone() | try expect_equal([1])

test "falling out of the match closes it once":
    let log: Shared[List[Int]] = share([])
    late(log) | try expect_equal(2)
    log.get().clone() | try expect_equal([2])
