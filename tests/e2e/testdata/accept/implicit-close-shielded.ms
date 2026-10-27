from "@std/core.ms" import Closeable, panic
from "@std/fs.ms" import filesystem
from "@std/tasks.ms" import TaskGroup
from "@std/test.ms" import expect_equal, expect_error, expect_fault, expect_ok, expect_true
from "@std/time.ms" import nanoseconds, sleep

# The scope-end close of a binding runs on every exit and is shielded like `with`: cancellation and a
# pending fault do not interrupt it, and a fault inside it follows the cleanup-failure table.
type Holder:
    dir: String
    id: Int
    pause: Bool
    breaks: Bool

# Close records itself by writing a marker file named after the holder.
impl Closeable for Holder:
    var def close() -> Unit:
        if self.pause:
            sleep(nanoseconds(5000000))

        let _ = filesystem().write_file(f"{self.dir}/{self.id}", "closed", True)
        if self.breaks:
            panic("close fault")

def closed(dir: String, id: Int) -> Bool:
    return filesystem().read_file(f"{dir}/{id}").is_ok()

def hold_and_wait(dir: String, id: Int, pause: Bool) -> Int:
    let holder = Holder(dir, id, pause, False)
    sleep(nanoseconds(5000000000))
    return holder.id

def hold_and_fault(dir: String, id: Int) -> Unit:
    let holder = Holder(dir, id, False, False)
    panic("body fault")

    let _ = holder.id

def hold_then_break(dir: String, id: Int) -> Unit:
    let holder = Holder(dir, id, False, True)
    let _ = holder.id

def hold_fault_and_break(dir: String, id: Int) -> Unit:
    let holder = Holder(dir, id, False, True)
    panic("body fault")

    let _ = holder.id

def cancel_a_holder(dir: String, id: Int, pause: Bool) -> Unit:
    with let group = TaskGroup[Int](timeout: some(nanoseconds(20000000))):
        group.spawn(lambda ch: hold_and_wait(dir.clone(), id, pause))

        let _ignored = group.wait()

test "cancellation closes the binding":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        cancel_a_holder(dir.clone(), 1, False)
        try expect_true(closed(dir, 1))

test "cancellation does not interrupt a close that suspends":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        cancel_a_holder(dir.clone(), 2, True)
        try expect_true(closed(dir, 2))

test "a fault unwinding the scope closes the binding":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        let message = try expect_fault(lambda: hold_and_fault(dir.clone(), 3))
        try expect_equal(message, "body fault")
        try expect_true(closed(dir, 3))

test "a faulted task closes its binding before the group reports":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        let mine = dir.clone()

        with let group = TaskGroup[Unit](contain_faults: True):
            group.spawn(lambda ch: hold_and_fault(mine.clone(), 4))

            let _reason = group.wait() | try expect_error

        try expect_true(closed(dir, 4))

test "a fault in close on a normal return is the fault":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        let message = try expect_fault(lambda: hold_then_break(dir.clone(), 5))
        try expect_equal(message, "close fault")
        try expect_true(closed(dir, 5))

test "a fault in close does not replace a pending fault":
    with let temporary = filesystem().temporary("manuscript-shield-") | try expect_ok:
        let dir = temporary.path()
        let message = try expect_fault(lambda: hold_fault_and_break(dir.clone(), 6))
        try expect_equal(message, "body fault")
        try expect_true(closed(dir, 6))
