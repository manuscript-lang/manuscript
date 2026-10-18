import {expect_true} from "@std/testing.ms"
import {Scheduler, TaskGroup} from "@std/tasks.ms"
import {duration, sleep} from "@std/time.ms"

fn pass() -> Result[Unit, Error]: return ok(unit)

test "scheduler bounds preserve omission none zero and positive meanings":
    with omitted = Scheduler():
        (omitted.start(pass).is_ok()) | try expect_true
    with absent = Scheduler(limit: none, history_limit: none, drain: none):
        (absent.start(pass).is_ok()) | try expect_true
    with zero = Scheduler(limit: 1, history_limit: 0, drain: duration(0)):
        (zero.start(pass).is_ok()) | try expect_true
    with maximum = Scheduler(
        limit: 9223372036854775807,
        history_limit: 9223372036854775807,
        drain: duration(9223372036854775807)
    ):
        (maximum.start(pass).is_ok()) | try expect_true

test "task timeout bounds and zero sleep retain existing behavior":
    with omitted = TaskGroup():
        (omitted.join().is_ok()) | try expect_true
    with absent = TaskGroup(timeout: none):
        (absent.join().is_ok()) | try expect_true
    with maximum = TaskGroup(timeout: duration(9223372036854775807)):
        (maximum.join().is_ok()) | try expect_true
    with zero = TaskGroup(timeout: duration(0)):
        let accepted_zero_timeout = 0
    sleep(duration(0))
