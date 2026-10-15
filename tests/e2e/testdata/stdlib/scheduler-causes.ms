import {Scheduler, SchedulerFailure} from "@std/tasks.ms"
import {category, ErrorCategory, TextError} from "@std/errors.ms"
import {IoError} from "@std/io.ms"
import Synchronized from "@std/sync.ms"
import sleep from "@std/time.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn typed_failure() -> Result[Unit, Error]:
    return error(IoError.Unavailable)

fn text_failure() -> Result[Unit, Error]:
    return error(TextError.Text("intentional text"))

test "scheduler failures retain typed and text causes":
    let seen = Synchronized(0)
    let reporter = fn(failure: SchedulerFailure) -> Unit:
        match failure:
            Failed(_, cause):
                with guard = seen.lock():
                    if category(cause) == some(ErrorCategory.Unavailable):
                        guard.set(guard.value + 1)

                    if cause.message() == "intentional text":
                        guard.set(guard.value + 10)
            _: unit

    with scheduler = Scheduler(reporter: reporter):
        value(scheduler.start(typed_failure))
        value(scheduler.start(text_failure))
        sleep(100.milliseconds)

    with guard = seen.lock():
        if guard.value != 11: return panic("scheduler causes were not retained")
