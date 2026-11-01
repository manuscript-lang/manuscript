import panic from "@std/core.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error from "@std/test/test.ms"

fn report(reason: TaskError) String:
    match reason:
        Faulted(report): return report.split("\n").get(0).clone()
        _: return reason.message()

test "closing a faulted group does not replace a later wait report":
    var first = TaskGroup[Unit](contain_faults: true)
    first.spawn(fn var ch: panic("first group fault"))

    let reason = first.wait() | try expect_error
    report(reason) | try expect_equal("first group fault")
    try first.close()

    var second = TaskGroup[Unit](contain_faults: true)
    second.spawn(fn var ch: panic("second group fault"))

    let next = second.wait() | try expect_error
    report(next) | try expect_equal("second group fault")

test "wait reports the first fault and leaves each task result readable":
    var group = TaskGroup[Unit](contain_faults: true)
    var first = group.spawn(fn var ch: panic("earlier task fault"))
    var second = group.spawn(fn var ch: panic("later task fault"))
    let waited = group.wait() | try expect_error
    report(waited) | try expect_equal("earlier task fault")

    let later = second.result() | try expect_error
    report(later) | try expect_equal("later task fault")

    let earlier = first.result() | try expect_error
    report(earlier) | try expect_equal("earlier task fault")
