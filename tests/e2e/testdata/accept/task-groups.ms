import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {TaskGroup, Task, ExecutionError} from "@std/tasks.ms"
import Synchronized from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"

type Stored:
    task: Task[Int]

fn forward[T](task: Task[T]) -> Task[T]:
    return task

fn exercise() -> Result[Unit, Error]:
    with group = TaskGroup():
        let start = group.start[Int]
        let number: Task[Int] = start(fn(): 41)
        let text = group.start(fn(): "hello")
        let domain = group.start(fn() -> Result[Int, String]: error("expected"))
        let stored = Stored(forward(number))
        let handles: List[Task[Int]] = [stored.task]
        let joined = try group.join()
        let joined_again = try group.join()
        let value = try stored.task.join()
        let value_again = try number.join()
        let message = try text.join()
        (value != 41 or value_again != 41 or message != "hello") | try expect_false

        for handle in handles:
            let saved_join: fn() -> Result[Int, ExecutionError] = handle.join
            let saved_value = try saved_join()
            saved_value | try expect_equal(expected: 41)

        let outcome = try domain.join()

        match outcome:
            error(cause):
                try expect_equal(cause, "expected")
            ok(_):
                return fail("domain error flattened")

        let resource = Closeable(group)
        resource.close()
        let after_close = try number.join()
        after_close | try expect_equal(expected: 41)

    with group = TaskGroup():
        let first = group.start(fn(): 1)
        let value = try first.join()
        let second = group.start(fn(): value + 1)
        let following = try second.join()
        following | try expect_equal(expected: 2)

    return ok(unit)

test "typed tasks group joins and cached outcomes":
    match exercise():
        ok(_):
            return
        error(_):
            return fail("task group failed")

test "empty group joins and closes repeatedly":
    with group = TaskGroup(0.seconds):
        match group.join():
            ok(_):
                group.close()
                group.close()
            error(_):
                return fail("empty group timed out")

test "zero timeout starts no callback":
    let calls = Synchronized(0)

    with group = TaskGroup(0.seconds):
        let task = group.start(
            fn() -> Unit:
                with count = calls.lock():
                    count.set(count.get() + 1)
        )

        let cause = match task.join():
            error(cause): cause
            ok(_): return fail("zero timeout succeeded")

        match cause:
            Timeout: unit
            _: return fail("wrong timeout outcome")

    with count = calls.lock():
        count.get() | try expect_equal(expected: 0)
