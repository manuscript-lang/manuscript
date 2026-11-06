import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Door:
    id: Int
    log: String

impl Closeable for Door:
    var fn close() Unit!:
        let _ = append_file(self.log, "{self.id},").wait()
        return ok(unit)

fn logged(path: String) String:
    let read = read_file(path).wait()
    if let bytes = read:
        return bytes.decode_utf8().get("")

    return ""

test "a list moved on one path closes on the path that keeps it":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    block(log.clone(), 1)
    logged(log.clone()) | try expect_equal("1,")

fn block(log: String, id: Int) Unit:
    let doors = [Door(id, log.clone())]
    var moved: List[Door]? = none
    if doors.length() == 0:
        moved = doors
    if moved.is_some():
        return

test "an optional resource reassigned after a conditional move closes the new value":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    reassign(log.clone())
    logged(log.clone()) | try expect_equal("1,2,")

fn reassign(log: String) Unit:
    var held: Door? = Door(1, log.clone())
    if var door = held:
        door.id = 1
    held = Door(2, log.clone())
    if held.is_none():
        return

fn walk(log: String, stop: Int) Unit:
    let doors = [Door(1, log.clone()), Door(2, log.clone()), Door(3, log.clone())]
    var kept = List[Door]()

    for door in doors:
        if door.id == stop:
            break

        if door.id == 1:
            kept.append(door)

test "a loop over owned resources closes each element it does not move":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    walk(log.clone(), 99)
    logged(log.clone()) | try expect_equal("2,3,1,")

test "a break closes the elements the loop never reached":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    walk(log.clone(), 1)
    logged(log.clone()) | try expect_equal("1,2,3,")

fn wrap(door: Door, log: String) List[Door]:
    var doors = [Door(9, log.clone())]
    doors.append(door)
    return doors

test "a binding built from a call that consumes a resource closes it":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    block_wrap(log.clone())
    logged(log.clone()) | try expect_equal("1,9,")

fn block_wrap(log: String) Unit:
    let made = wrap(Door(1, log.clone()), log.clone())
    if made.length() == 0:
        return

enum Shape:
    Circle(door: Door)
    Empty

fn shape(log: String) Shape:
    return Shape.Circle(Door(5, log.clone()))

test "a match on a temporary resource closes it when the match ends":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    var seen = 0

    match shape(log.clone()):
        Circle(door):
            seen = door.id
        _:
            seen = 0

    expect_equal(seen, 5) | try
    logged(log.clone()) | try expect_equal("5,")
