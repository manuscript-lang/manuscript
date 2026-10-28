from "@std/core.ms" import panic
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/test.ms" import expect_equal, expect_error

def report(reason: TaskError) -> String:
    match reason:
        case Faulted(report): return report.split("\n").get(0).clone()
        case _: return reason.message()

test "closing a faulted group does not replace a later wait report":
    var first = TaskGroup[Unit](contain_faults: True)
    first.spawn(lambda ch: panic("first group fault"))

    let reason = first.wait() | try expect_error
    report(reason) | try expect_equal("first group fault")
    first.close()

    let second = TaskGroup[Unit](contain_faults: True)
    second.spawn(lambda ch: panic("second group fault"))

    let next = second.wait() | try expect_error
    report(next) | try expect_equal("second group fault")

test "wait reports the first fault and leaves each task result readable":
    let group = TaskGroup[Unit](contain_faults: True)
    let first = group.spawn(lambda ch: panic("earlier task fault"))
    let second = group.spawn(lambda ch: panic("later task fault"))
    let waited = group.wait() | try expect_error
    report(waited) | try expect_equal("earlier task fault")

    let later = second.result() | try expect_error
    report(later) | try expect_equal("later task fault")

    let earlier = first.result() | try expect_error
    report(earlier) | try expect_equal("earlier task fault")
