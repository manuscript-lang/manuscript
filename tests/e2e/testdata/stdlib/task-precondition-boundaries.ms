import panic from "@std/faults.ms"
import {Scheduler, TaskGroup} from "@std/tasks.ms"
import {duration, sleep} from "@std/time.ms"

fn pass() -> Result[Unit, Error]: return ok(unit)

test "scheduler bounds preserve omission none zero and positive meanings":
    with omitted = Scheduler():
        if not omitted.start(pass).is_ok(): return panic("omitted scheduler")

    with absent = Scheduler(limit: none, history_limit: none, drain: none):
        if not absent.start(pass).is_ok(): return panic("none scheduler")

    with zero = Scheduler(
        limit: 1,
        history_limit: 0,
        drain: duration(0)
    ):
        if not zero.start(pass).is_ok(): return panic("zero history/drain")

    with maximum = Scheduler(
        limit: 9223372036854775807,
        history_limit: 9223372036854775807,
        drain: duration(9223372036854775807)
    ):
        if not maximum.start(pass).is_ok(): return panic("maximum bounds")

test "task timeout bounds and zero sleep retain existing behavior":
    with omitted = TaskGroup():
        if not omitted.join().is_ok(): return panic("omitted timeout")

    with absent = TaskGroup(timeout: none):
        if not absent.join().is_ok(): return panic("none timeout")

    with maximum = TaskGroup(timeout: duration(9223372036854775807)):
        if not maximum.join().is_ok(): return panic("maximum timeout")

    with zero = TaskGroup(timeout: duration(0)):
        let accepted_zero_timeout = 0

    sleep(duration(0))
