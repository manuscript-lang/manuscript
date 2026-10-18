import {expect_equal} from "@std/testing.ms"
import {Scheduler, SchedulerFailure} from "@std/tasks.ms"
import {category, ErrorCategory, TextError} from "@std/errors.ms"
import {IoError} from "@std/io.ms"
import Synchronized from "@std/sync.ms"
import sleep from "@std/time.ms"

fn typed_failure() Result[Unit, Error]:
    return error(IoError.Unavailable)

fn text_failure() Result[Unit, Error]:
    return error(TextError.Text("intentional text"))

test "scheduler failures retain typed and text causes":
    let seen = Synchronized(0)
    let reporter = fn(failure: SchedulerFailure) Unit:
        match failure:
            Failed(_, cause):
                with guard = seen.lock():
                    if category(cause) == some(ErrorCategory.Unavailable):
                        guard.set(guard.get() + 1)
                    if cause.message() == "intentional text":
                        guard.set(guard.get() + 10)
            _: unit

    with scheduler = Scheduler(reporter: reporter):
        let _typed = try scheduler.start(typed_failure)
        let _text = try scheduler.start(text_failure)
        sleep(100.milliseconds)

    with guard = seen.lock():
        try expect_equal(guard.get(), 11)
