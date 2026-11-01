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

fn first_even(var log: Shared[List[Int]]) Int:
    let doors = [Door(1, log), Door(2, log), Door(3, log)]
    for d in doors:
        if d.id % 2 == 0:
            return d.id
    return -1

fn until_two(var log: Shared[List[Int]]) Int:
    let doors = [Door(1, log), Door(2, log), Door(3, log)]
    var n = 0

    for d in doors:
        n = n + d.id
        if d.id == 2:
            break

    return n

test "return out of an owned loop closes every element once":
    var log: Shared[List[Int]] = Shared([])
    first_even(var log) | try expect_equal(2)
    log.clone() | try expect_equal([1, 2, 3])

test "break closes the elements it never reached":
    var log: Shared[List[Int]] = Shared([])
    until_two(var log) | try expect_equal(3)
    log.clone() | try expect_equal([1, 2, 3])
