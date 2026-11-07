import Closeable from "@std/core.ms"
import append_file, read_file, temporary, write_file from "@std/os/fs.ms"
import expect_equal, expect_fault, expect_ok from "@std/test/test.ms"

type Marker:
    id: Int
    log: String
    fail: Bool

impl Closeable for Marker:
    var fn close() Unit!:
        try append_file(self.log, "{self.id},").wait()
        if self.fail: return error(Error("cause close failed"))

        return ok(unit)

fn source(log: String) Marker?: Marker(1, log, false)

fn discard(log: String) Unit:
    let _kept = source(log.clone()).ok_or(Marker(2, log, true))

test "closing an unused cause does not lose the retained receiver on fault":
    let tmp = temporary("cause-fault-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()

    let _fault = try expect_fault(fn: discard(log.clone()))
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "2,1,")

fn normal_transfer(log: String) Unit!:
    let kept = source(log.clone()).ok_or(Marker(2, log.clone(), false))
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "2,")
    try expect_equal(kept.get().id, 1)
    return ok(unit)

test "successful cause cleanup transfers the protected receiver exactly once":
    let tmp = temporary("cause-transfer-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()
    try normal_transfer(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "2,1,")

fn failing_callback(log: String) fn() Marker:
    let captured = Marker(2, log, true)
    return fn: Marker(3, captured.log.clone(), false)

fn discard_callback(log: String) Unit:
    let _kept = source(log.clone()).ok_or_else(failing_callback(log))

// Capture closer thunks discard returned close errors; this is a cleanup control, not a fault.
test "unused owning callback cleanup closes its capture without invoking the callback":
    let tmp = temporary("cause-callback-fault-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()
    discard_callback(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "2,1,")
