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

fn keep_if(d: Door, keep: Bool) Door?:
    if keep:
        return d

    return none

test "a parameter the callee drops on some path is closed there":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    let kept = keep_if(Door(1, log.clone()), true)
    logged(log.clone()) | try expect_equal("")

    let dropped = keep_if(Door(2, log.clone()), false)
    logged(log.clone()) | try expect_equal("2,")
    if kept.is_some() and dropped.is_none():
        logged(log.clone()) | try expect_equal("2,")

test "a bound resource passed to such a callee closes once":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    let door = Door(3, log.clone())
    let dropped = keep_if(door, false)
    logged(log.clone()) | try expect_equal("3,")
    if dropped.is_none():
        logged(log.clone()) | try expect_equal("3,")
