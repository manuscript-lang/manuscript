import {expect_equal, expect_ok} from "@std/test.ms"
import Closeable from "@std/core.ms"
import filesystem from "@std/fs.ms"
import {Shared, share} from "@std/shared.ms"
import lock from "@std/sync.ms"

# Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
    log: String
    id: Int

impl Closeable for Tracked:
    var fn close() Unit:
        let _ = filesystem().append_file(self.log, "{self.id},")

fn closed(log: String) String:
    if let bytes = filesystem().read_file(log):
        return bytes.decode_utf8().get("")

    return ""

fn last_holder(log: String) Int:
    let first = share(Tracked(log, 1))
    let second = first
    return second.get().id

fn other_holder_lives(log: String) Shared[Tracked]:
    let first = share(Tracked(log, 1))
    let second = first
    return second

fn locked_then_dropped(log: String) Int:
    let box = share(Tracked(log, 1))
    with var guard = lock(box):
        guard.value.id += 0
    return 0

test "the last holder closes the payload":
    with let temporary = filesystem().temporary("manuscript-shared-") | try expect_ok:
        let log = "{temporary.path()}/log"
        try expect_equal(last_holder(log.clone()), 1)
        try expect_equal(closed(log), "1,")

test "a holder handed to the caller keeps the payload open":
    with let temporary = filesystem().temporary("manuscript-shared-") | try expect_ok:
        let log = "{temporary.path()}/log"
        let kept = other_holder_lives(log.clone())
        try expect_equal(closed(log.clone()), "")
        try expect_equal(kept.get().id, 1)

test "a payload locked and released is closed once":
    with let temporary = filesystem().temporary("manuscript-shared-") | try expect_ok:
        let log = "{temporary.path()}/log"
        try expect_equal(locked_then_dropped(log.clone()), 0)
        try expect_equal(closed(log), "1,")
