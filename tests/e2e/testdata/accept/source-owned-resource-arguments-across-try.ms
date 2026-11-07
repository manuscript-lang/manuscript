import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Marker:
    id: Int
    log: String
    closed: Bool = false

impl Closeable for Marker:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()

        return ok(unit)

fn successful_value() Int!:
    return ok(7)

fn failed_value() Int!:
    return error(Error("expected argument failure"))

fn consume(marker: Marker, value: Int) Int:
    let markers = [marker]
    return markers.length() + value

fn successful_call(log: String) Int!:
    let marker = Marker(1, log)
    return ok(consume(marker, try successful_value()))

fn failed_call(log: String) Int!:
    let marker = Marker(2, log)
    return ok(consume(marker, try failed_value()))

fn consume_with_default(
    marker: Marker,
    value: Int,
    extra: Int = try failed_value()
) Int!:
    let markers = [marker]
    return ok(markers.length() + value + extra)

fn failed_default(log: String) Int!:
    let marker = Marker(3, log)
    return consume_with_default(marker, try successful_value())

test "source resource arguments close once on success and early argument exits":
    let tmp = temporary("source-owned-try-") | try expect_ok
    let log = "{tmp.path()}/log"
    try expect_equal((try successful_call(log.clone())), 8)
    try expect_equal(failed_call(log.clone()).is_error(), true)
    try expect_equal(failed_default(log.clone()).is_error(), true)

    let events = read_file(log).wait().get().decode_utf8().get("")
    try expect_equal(events, "1,2,3,")
