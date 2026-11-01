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

fn open(id: Int, var log: Shared[List[Int]]) Door?:
    return Door(id, log)

fn early(var log: Shared[List[Int]]) Int:
    match open(1, var log):
        d:
            if d.id == 1:
                return 10

            return 20
        none:
            return 0

fn late(var log: Shared[List[Int]]) Int:
    let n = match open(2, var log):
        d: d.id
        none: 0

    return n

fn hand_on(var log: Shared[List[Int]]) Door?:
    match open(3, var log):
        d: return d
        none: return none

test "a payload moved out of the arm is not closed by the match":
    var log: Shared[List[Int]] = Shared([])
    let kept = hand_on(var log)
    log.clone() | try expect_equal([])
    if kept.is_some():
        log.clone() | try expect_equal([])

test "return from an arm closes the temporary scrutinee once":
    var log: Shared[List[Int]] = Shared([])
    early(var log) | try expect_equal(10)
    log.clone() | try expect_equal([1])

test "falling out of the match closes it once":
    var log: Shared[List[Int]] = Shared([])
    late(var log) | try expect_equal(2)
    log.clone() | try expect_equal([2])
