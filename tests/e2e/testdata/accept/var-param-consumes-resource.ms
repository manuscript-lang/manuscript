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

type Slot:
    door: Door

fn logged(path: String) String:
    let read = read_file(path).wait()
    if let bytes = read:
        return bytes.decode_utf8().get("")

    return ""

fn put(var slot: Slot, door: Door) Unit:
    slot.door = door

fn stash(var doors: List[Door], door: Door) Unit:
    doors.append(door)

test "a temporary passed to a var-parameter function that keeps it closes once, later":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    var slot = Slot(Door(1, log.clone()))
    put(var slot, Door(2, log.clone()))
    logged(log.clone()) | try expect_equal("1,")
    expect_equal(slot.door.id, 2) | try

test "a list a var-parameter function appends a temporary to closes it with the list":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    var doors = List[Door]()
    stash(var doors, Door(3, log.clone()))
    logged(log.clone()) | try expect_equal("")
    expect_equal(doors.length(), 1) | try
