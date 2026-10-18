import {expect_false} from "@std/testing.ms"
import {Scheduler, TaskGroup} from "@std/tasks.ms"
import {duration, sleep} from "@std/time.ms"

fn pass() Result[Unit, Error]: return ok(unit)

test "scheduler bounds preserve omission none zero and positive meanings":
    with omitted = Scheduler():
        try expect_false(not omitted.start(pass).is_ok())
    with absent = Scheduler(none, none, none):
        try expect_false(not absent.start(pass).is_ok())
    with zero = Scheduler(1, 0, duration(0)):
        try expect_false(not zero.start(pass).is_ok())
    with maximum = Scheduler(
        9223372036854775807,
        9223372036854775807,
        duration(9223372036854775807)
    ):
        try expect_false(not maximum.start(pass).is_ok())

test "task timeout bounds and zero sleep retain existing behavior":
    with omitted = TaskGroup():
        try expect_false(not omitted.join().is_ok())
    with absent = TaskGroup(none):
        try expect_false(not absent.join().is_ok())
    with maximum = TaskGroup(duration(9223372036854775807)):
        try expect_false(not maximum.join().is_ok())
    with zero = TaskGroup(duration(0)):
        try expect_false(not zero.join().is_ok())
    sleep(duration(0))
