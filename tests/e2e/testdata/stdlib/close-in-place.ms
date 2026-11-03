import expect_equal, expect_fault, expect_ok from "@std/test/test.ms"
import Closeable, panic from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"

// A close that changes its receiver works on the value where it lives: a holder, a part, a
// closure's capture or the cleanup stack sees the closed state afterwards, so a second close of
// the same value (an explicit close followed by the scope end) logs nothing.
type Latch:
    log: String
    id: Int
    open: Bool

impl Closeable for Latch:
    var fn close() Unit!:
        if self.open:
            self.open = false

            let _ = append_file(self.log, "{self.id},")

        return ok(unit)

fn latch(log: String, id: Int) Latch:
    return Latch(log, id, true)

fn closed(log: String) String:
    if let bytes = read_file(log):
        return bytes.decode_utf8().get("")

    return ""

type Holder:
    inner: Latch
    tag: Int

type Slot:
    case Full(inner: Latch)
    case Empty

fn explicit_then_scope(log: String) Int!:
    var one = latch(log, 1)
    try one.close()
    return ok(1)

fn holder_part(log: String) Int:
    let holder = Holder(latch(log, 2), 0)
    return holder.tag

fn optional_part(log: String) Int:
    let maybe: Latch? = latch(log, 3)
    if maybe.is_some():
        return 1

    return 0

fn list_parts(log: String) Int:
    let xs = [latch(log.clone(), 4), latch(log, 5)]
    return xs.length()

fn case_part(log: String) Int:
    let slot = Full(latch(log, 6))

    let n = match slot:
        Full(inner): inner.id
        Empty: 0

    return n

fn make_closure(log: String) fn() Int:
    let held = latch(log, 7)
    return fn: held.id

fn closure_capture(log: String) Int:
    let f = make_closure(log)
    return f()

fn map_values(log: String) Int:
    var m = Map[String, Latch]()
    m.add("a", latch(log, 8))
    return m.length()

fn fault_through_holder(log: String) Unit:
    let holder = Holder(latch(log, 9), 0)
    panic("holder fault")

    let _ = holder.tag

fn fault_plain(log: String) Unit:
    let one = latch(log, 10)
    panic("plain fault")

    let _ = one.id

fn reassigned(log: String, swap: Bool) Int:
    var one = latch(log.clone(), 11)
    if swap:
        one = latch(log, 12)
    return one.id

test "an explicit close followed by the scope end closes once":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(try explicit_then_scope(log.clone()), 1)
    try expect_equal(closed(log), "1,")

test "a holder's part closes in place at the scope end":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holder_part(log.clone()), 0)
    try expect_equal(closed(log), "2,")

test "an optional payload closes in place":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(optional_part(log.clone()), 1)
    try expect_equal(closed(log), "3,")

test "list elements close in place, last first":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(list_parts(log.clone()), 2)
    try expect_equal(closed(log), "5,4,")

test "a case field closes in place":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(case_part(log.clone()), 6)
    try expect_equal(closed(log), "6,")

test "a closure's capture closes when the closure is dropped":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(closure_capture(log.clone()), 7)
    try expect_equal(closed(log), "7,")

test "map values close in place":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(map_values(log.clone()), 1)
    try expect_equal(closed(log), "8,")

test "a fault closes a holder's part from the cleanup stack":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    let message = try expect_fault(fn: fault_through_holder(log.clone()))
    try expect_equal(message, "holder fault")
    try expect_equal(closed(log), "9,")

test "a fault closes a plain binding from the cleanup stack":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    let message = try expect_fault(fn: fault_plain(log.clone()))
    try expect_equal(message, "plain fault")
    try expect_equal(closed(log), "10,")

test "a reassigned binding closes the replaced value then the final one":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(reassigned(log.clone(), true), 12)
    try expect_equal(closed(log), "11,12,")

test "a binding kept to the end closes once":
    let temporary = temporary("manuscript-close-in-place-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(reassigned(log.clone(), false), 11)
    try expect_equal(closed(log), "11,")
