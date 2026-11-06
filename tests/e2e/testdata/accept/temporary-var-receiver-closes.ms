import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Door:
    id: Int
    log: String
    swings: Int

impl Closeable for Door:
    var fn close() Unit!:
        let _ = append_file(self.log, "{self.id},")
        return ok(unit)

impl Door:
    var fn swing() Int:
        self.swings += 1
        return self.swings

    fn peek() Int:
        return self.swings

fn logged(path: String) String:
    let read = read_file(path).wait()
    if let bytes = read:
        return bytes.decode_utf8().get("")

    return ""

fn open_door(id: Int, log: String) Door:
    return Door(id, log, 0)

// A temporary that a `var fn` changes in place is still a temporary: it closes when its statement ends.
test "a temporary receiver of a var method closes at the end of its statement":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    let first = open_door(1, log.clone()).swing()
    let second = open_door(2, log.clone()).peek()
    try expect_equal(first + second, 1)
    try expect_equal(logged(log), "1,2,")
