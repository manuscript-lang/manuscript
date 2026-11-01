import Closeable from "@std/core.ms"
import Shared, share from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

type Door:
    id: Int
    log: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit!:
        var seen = self.log.lock()
        seen.value.append(self.id)
        return ok(unit)

type Slot:
    door: Door

fn put(var slot: Slot, door: Door) Unit:
    slot.door = door

fn stash(var doors: List[Door], door: Door) Unit:
    doors.append(door)

test "a temporary passed to a var-parameter function that keeps it closes once, later":
    let log: Shared[List[Int]] = share([])
    var slot = Slot(Door(1, log))
    put(var slot, Door(2, log))
    log.get().clone() | try expect_equal([1])
    expect_equal(slot.door.id, 2) | try

test "a list a var-parameter function appends a temporary to closes it with the list":
    let log: Shared[List[Int]] = share([])
    var doors = List[Door]()
    stash(var doors, Door(3, log))
    log.get().clone() | try expect_equal([])
    expect_equal(doors.length(), 1) | try
