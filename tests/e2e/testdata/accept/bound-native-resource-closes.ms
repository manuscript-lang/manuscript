import Closeable from "@std/core.ms"
import append_file, read_file, remove, temporary, temporary_root from "@std/os/fs.ms"
import secure_int from "@std/random.ms"
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
    status := failed(1, log.clone()).is_error
    try expect_equal(status(), true)
    try expect_equal(status(), true)
    try expect_equal(read_file(log).wait().is_error(), true)
    return ok(unit)

test "a bound native method owns its temporary receiver and closes it once":
    tmp := temporary("bound-native-close-") | try expect_ok
    log := "{tmp.path()}/log"
    try call_twice(log.clone())
    try expect_equal(events(log), "1,")

fn named(log: String) Unit!:
    held := failed(2, log.clone())
    status := held.is_error
    try expect_equal(status(), true)
    return ok(unit)

test "a bound native method over a named receiver closes it once, not twice":
    tmp := temporary("bound-native-named-") | try expect_ok
    log := "{tmp.path()}/log"
    try named(log.clone())
    try expect_equal(events(log), "2,")

// A resource with only scalar fields has no drop glue but still has one owner that closes it. Its
// id names the file the close appends to, since it has nowhere to keep a log path.
type Tag:
    id: Int

// The host temp root, since a hard-coded /tmp does not exist on Windows.
fn tag_log(id: Int) String!:
    return ok("{try temporary_root()}/ms-bound-native-tag-{id}")

impl Closeable for Tag:
    var fn close() Unit!:
        try append_file(try tag_log(self.id), "closed,").wait()
        return ok(unit)

fn borrowed_status(result: Int!Tag) Bool:
    check := result.is_error
    return check()

test "a method value over a borrowed scalar resource leaves the close to its owner":
    id := try secure_int(1, 1000000000)
    log := try tag_log(id)
    try borrow_then_check(id, log.clone())
    try expect_equal(events(log.clone()), "closed,")
    try remove(log)

fn borrow_then_check(id: Int, log: String) Unit!:
    result: Int!Tag = error(Tag(id))
    try expect_equal(borrowed_status(result), true)
    try expect_equal(read_file(log.clone()).wait().is_error(), true)
    return ok(unit)
