import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Marker:
    id: Int
    log: String

impl Closeable for Marker:
    var fn close() Unit!:
        try append_file(self.log, "{self.id},").wait()
        return ok(unit)

fn failed(id: Int, log: String) Int!Marker:
    return error(Marker(id, log))

fn events(log: String) String:
    return read_file(log).wait().get().decode_utf8().get("")

fn call_twice(log: String) Unit!:
    let status = failed(1, log.clone()).is_error
    try expect_equal(status(), true)
    try expect_equal(status(), true)
    try expect_equal(read_file(log).wait().is_error(), true)
    return ok(unit)

test "a bound native method owns its temporary receiver and closes it once":
    let tmp = temporary("bound-native-close-") | try expect_ok
    let log = "{tmp.path()}/log"
    try call_twice(log.clone())
    try expect_equal(events(log), "1,")

fn named(log: String) Unit!:
    let held = failed(2, log.clone())
    let status = held.is_error
    try expect_equal(status(), true)
    return ok(unit)

test "a bound native method over a named receiver closes it once, not twice":
    let tmp = temporary("bound-native-named-") | try expect_ok
    let log = "{tmp.path()}/log"
    try named(log.clone())
    try expect_equal(events(log), "2,")
