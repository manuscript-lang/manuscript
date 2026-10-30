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

fn first_even(log: Shared[List[Int]]) Int:
    let doors = [Door(1, log), Door(2, log), Door(3, log)]
    for d in doors:
        if d.id % 2 == 0:
            return d.id
    return -1

fn until_two(log: Shared[List[Int]]) Int:
    let doors = [Door(1, log), Door(2, log), Door(3, log)]
    var n = 0

    for d in doors:
        n = n + d.id
        if d.id == 2:
            break

    return n

test "return out of an owned loop closes every element once":
    let log: Shared[List[Int]] = share([])
    first_even(log) | try expect_equal(2)
    log.get().clone() | try expect_equal([1, 2, 3])

test "break closes the elements it never reached":
    let log: Shared[List[Int]] = share([])
    until_two(log) | try expect_equal(3)
    log.get().clone() | try expect_equal([1, 2, 3])
