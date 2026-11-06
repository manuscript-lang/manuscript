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

fn open(id: Int, log: String) Door?:
    return Door(id, log.clone())

fn early(log: String) Int:
    match open(1, log.clone()):
        d:
            if d.id == 1:
                return 10

            return 20
        none:
            return 0

fn late(log: String) Int:
    let n = match open(2, log.clone()):
        d: d.id
        none: 0

    return n

fn hand_on(log: String) Door?:
    match open(3, log.clone()):
        d: return d
        none: return none

test "a payload moved out of the arm is not closed by the match":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    let kept = hand_on(log.clone())
    logged(log.clone()) | try expect_equal("")
    if kept.is_some():
        logged(log.clone()) | try expect_equal("")

test "return from an arm closes the temporary scrutinee once":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    early(log.clone()) | try expect_equal(10)
    logged(log.clone()) | try expect_equal("1,")

test "falling out of the match closes it once":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    late(log.clone()) | try expect_equal(2)
    logged(log.clone()) | try expect_equal("2,")
