import expect_equal, expect_ok from "@std/test/test.ms"
import Source, Sink, stream, writer from "@std/io/io.ms"
import Promise, deferred, complete from "@std/concurrency/promise.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"

// A stream closes its source or sink once, whether the stream is closed by hand or dropped.
type Counted:
    log: String

impl Source[Int] for Counted:
    var fn next() Int?!:
        return ok(none)

    var fn close() Unit!:
        let _ = append_file(self.log, "r")
        return ok(unit)

impl Sink[Int] for Counted:
    var fn put(value: Int) Unit!:
        return ok(unit)

    var fn drain() Promise[Unit]:
        return deferred[Unit](fn(id: Int) Unit: complete[Unit](id, ok(unit)))

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        let _ = append_file(self.log, "w")
        return ok(unit)

fn closes(log: String) String:
    if let bytes = read_file(log).wait():
        return bytes.decode_utf8().get("")

    return ""

test "a read stream closes its source once":
    let dir = temporary("stream-close-") | try expect_ok
    let log = "{dir.path()}/r.log"
    let _ = append_file(log, "")
    var by_hand = stream[Int](Counted(log.clone()))
    try by_hand.close()
    try expect_equal(closes(log), "r")

test "a write stream closes its sink once":
    let dir = temporary("stream-close-") | try expect_ok
    let log = "{dir.path()}/w.log"
    let _ = append_file(log, "")
    var out = writer[Int](Counted(log.clone()))
    try out.close()
    try expect_equal(closes(log), "w")

type Failing:
    unused: Int

impl Source[Int] for Failing:
    var fn next() Int?!:
        return ok(none)

    var fn close() Unit!:
        return error(Error("close failed", kind: "EIO"))

test "an explicit close returns the source's close error":
    var input = stream[Int](Failing(0))
    let result = input.close()
    try expect_equal(result.is_error(), true)
    try expect_equal(result.err().message, "close failed")
