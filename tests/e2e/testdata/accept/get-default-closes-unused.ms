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

fn present(log: Shared[List[Int]]) Int:
    let held: Door? = Door(1, log)
    let door = held.get(Door(2, log))
    return door.id

fn absent(log: Shared[List[Int]]) Int:
    let held: Door? = none
    let door = held.get(Door(3, log))
    return door.id

fn named(log: Shared[List[Int]]) Int:
    let held: Door? = Door(4, log)
    let spare = Door(5, log)
    let door = held.get(spare)
    return door.id + spare.id

test "an unused temporary default closes at once":
    let log: Shared[List[Int]] = Shared([])
    expect_equal(present(log), 1) | try
    log.clone() | try expect_equal([2, 1])

test "a used default closes with its binding":
    let log: Shared[List[Int]] = Shared([])
    expect_equal(absent(log), 3) | try
    log.clone() | try expect_equal([3])

test "a named default the caller keeps is not closed early":
    let log: Shared[List[Int]] = Shared([])
    expect_equal(named(log), 9) | try
    log.clone() | try expect_equal([4, 5])
