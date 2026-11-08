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

fn present(log: String) Int:
    let held: Door? = Door(1, log.clone())
    let door = held.get(Door(2, log.clone()))
    return door.id

fn absent(log: String) Int:
    let held: Door? = none
    let door = held.get(Door(3, log.clone()))
    return door.id

fn named(log: String) Int:
    let held: Door? = Door(4, log.clone())
    let spare = Door(5, log.clone())
    let door = held.get(spare)
    return door.id + 8

test "an unused temporary default closes at once":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    expect_equal(present(log.clone()), 1) | try
    logged(log.clone()) | try expect_equal("2,1,")

test "a used default closes with its binding":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    expect_equal(absent(log.clone()), 3) | try
    logged(log.clone()) | try expect_equal("3,")

test "a named default moves into get and closes with the call":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    expect_equal(named(log.clone()), 12) | try
    logged(log.clone()) | try expect_equal("5,4,")
