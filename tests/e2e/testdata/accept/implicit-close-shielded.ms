import Closeable, panic from "@std/core.ms"
import filesystem from "@std/fs.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal, expect_error, expect_fault, expect_ok, expect_true from "@std/test.ms"
import nanoseconds, sleep from "@std/time.ms"

# The scope-end close of a binding runs on every exit and is shielded like any other close: cancellation and a
# pending fault do not interrupt it, and a fault inside it follows the cleanup-failure table.
type Holder:
    dir: String
    id: Int
    pause: Bool
    breaks: Bool

# Close records itself by writing a marker file named after the holder.
impl Closeable for Holder:
    var fn close() Unit:
        if self.pause:
            sleep(nanoseconds(5000000))

        let _ = filesystem().write_file("{self.dir}/{self.id}", "closed", true)
        if self.breaks:
            panic("close fault")

fn closed(dir: String, id: Int) Bool:
    return filesystem().read_file("{dir}/{id}").is_ok()

fn hold_and_wait(dir: String, id: Int, pause: Bool) Int:
    let holder = Holder(dir, id, pause, false)
    sleep(nanoseconds(5000000000))
    return holder.id

fn hold_and_fault(dir: String, id: Int) Unit:
    let holder = Holder(dir, id, false, false)
    panic("body fault")

    let _ = holder.id

fn hold_then_break(dir: String, id: Int) Unit:
    let holder = Holder(dir, id, false, true)
    let _ = holder.id

fn hold_fault_and_break(dir: String, id: Int) Unit:
    let holder = Holder(dir, id, false, true)
    panic("body fault")

    let _ = holder.id

fn cancel_a_holder(dir: String, id: Int, pause: Bool) Unit:
    let group = TaskGroup[Int](timeout: some(nanoseconds(20000000)))
    group.spawn(fn ch: hold_and_wait(dir.clone(), id, pause))

    let _ignored = group.wait()

test "cancellation closes the binding":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    cancel_a_holder(dir.clone(), 1, false)
    try expect_true(closed(dir, 1))

test "cancellation does not interrupt a close that suspends":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    cancel_a_holder(dir.clone(), 2, true)
    try expect_true(closed(dir, 2))

test "a fault unwinding the scope closes the binding":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    let message = try expect_fault(fn: hold_and_fault(dir.clone(), 3))
    try expect_equal(message, "body fault")
    try expect_true(closed(dir, 3))

test "a faulted task closes its binding before the group reports":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    let mine = dir.clone()
    var group = TaskGroup[Unit](contain_faults: true)
    group.spawn(fn ch: hold_and_fault(mine.clone(), 4))

    let _reason = group.wait() | try expect_error
    group.close()
    try expect_true(closed(dir, 4))

test "a fault in close on a normal return is the fault":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    let message = try expect_fault(fn: hold_then_break(dir.clone(), 5))
    try expect_equal(message, "close fault")
    try expect_true(closed(dir, 5))

test "a fault in close does not replace a pending fault":
    let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok
    let dir = temporary.path()
    let message = try expect_fault(fn: hold_fault_and_break(dir.clone(), 6))
    try expect_equal(message, "body fault")
    try expect_true(closed(dir, 6))
