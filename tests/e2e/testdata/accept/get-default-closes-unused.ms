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

fn present(var log: Shared[List[Int]]) Int:
    let held: Door? = Door(1, log)
    let door = held.get(Door(2, log))
    return door.id

fn absent(var log: Shared[List[Int]]) Int:
    let held: Door? = none
    let door = held.get(Door(3, log))
    return door.id

fn named(var log: Shared[List[Int]]) Int:
    let held: Door? = Door(4, log)
    let spare = Door(5, log)
    let door = held.get(spare)
    return door.id + spare.id

test "an unused temporary default closes at once":
    var log: Shared[List[Int]] = Shared([])
    expect_equal(present(var log), 1) | try
    log.clone() | try expect_equal([2, 1])

test "a used default closes with its binding":
    var log: Shared[List[Int]] = Shared([])
    expect_equal(absent(var log), 3) | try
    log.clone() | try expect_equal([3])

test "a named default the caller keeps is not closed early":
    var log: Shared[List[Int]] = Shared([])
    expect_equal(named(var log), 9) | try
    log.clone() | try expect_equal([4, 5])
