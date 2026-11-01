import expect_equal, expect_ok from "@std/test/test.ms"
import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import Shared from "@std/concurrency/shared.ms"

# Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
    log: String
    id: Int

impl Closeable for Tracked:
    var fn close() Unit!:
        let _ = append_file(self.log, "{self.id},")
        return ok(unit)

fn closed(log: String) String:
    if let bytes = read_file(log):
        return bytes.decode_utf8().get("")

    return ""

fn last_holder(log: String) Int:
    var first = Shared(Tracked(log, 1))
    let second = first
    return second.id

fn other_holder_lives(log: String) Shared[Tracked]:
    var first = Shared(Tracked(log, 1))
    var second = first
    return second

fn changed_then_dropped(log: String) Int:
    var box = Shared(Tracked(log, 1))
    box.id += 0
    return 0

test "the last holder closes the payload":
    let temporary = temporary("manuscript-shared-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(last_holder(log.clone()), 1)
    try expect_equal(closed(log), "1,")

test "a holder handed to the caller keeps the payload open":
    let temporary = temporary("manuscript-shared-") | try expect_ok
    let log = "{temporary.path()}/log"
    let kept = other_holder_lives(log.clone())
    try expect_equal(closed(log.clone()), "")
    try expect_equal(kept.id, 1)

test "a payload changed through its handle is closed once":
    let temporary = temporary("manuscript-shared-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(changed_then_dropped(log.clone()), 0)
    try expect_equal(closed(log), "1,")
