import {TaskGroup, Task, ExecutionError} from "@std/tasks.ms"
import Result from "@std/result.ms"
import List from "@std/collections.ms"
import Closeable from "@std/cleanup.ms"
import panic from "@std/faults.ms"

type Stored:
    task: Task[Int]

fn forward[T](task: Task[T]) -> Task[T]:
    return task

fn exercise() -> Result[Unit, ExecutionError]:
    with group = TaskGroup():
        let start = group.start[Int]
        let number: Task[Int] = start(
            fn() -> Int: return 41
        )
        let text = group.start(
            fn() -> String: return "hello"
        )
        let domain = group.start(
            fn() -> Result[Int, String]: return error(cause: "expected")
        )
        let stored = Stored(task: forward(number))
        let handles: List[Task[Int]] = [stored.task]
        let joined = try group.join()
        let joined_again = try group.join()
        let value = try stored.task.join()
        let value_again = try number.join()
        let message = try text.join()
        if (
            value != 41
            or value_again != 41
            or message != "hello"
        ):
            return panic("typed results changed")

        for handle in handles:
            let saved_join: fn() -> Result[Int, ExecutionError] = handle.join
            let saved_value = try saved_join()
            if saved_value != 41:
                return panic("saved task join changed")

        let outcome = try domain.join()

        match outcome:
            error(cause):
                if cause != "expected":
                    return panic("domain error changed")

            ok(_):
                return panic("domain error flattened")

        let resource = Closeable(value: group)
        resource.close()
        let after_close = try number.join()
        if after_close != 41:
            return panic("close erased result")

    with group = TaskGroup():
        let first = group.start(
            fn() -> Int: return 1
        )
        let value = try first.join()
        let second = group.start(
            fn() -> Int: return value + 1
        )
        let following = try second.join()
        if following != 2:
            return panic("individual join sealed group")

    return ok(value: unit)

test "typed tasks group joins and cached outcomes":
    match exercise():
        ok(_):
            return

        error(_):
            return panic("task group failed")

test "empty group joins and closes repeatedly":
    with group = TaskGroup(timeout: 0.seconds):
        match group.join():
            ok(_):
                group.close()
                group.close()

            error(_):
                return panic("empty group timed out")

test "zero timeout starts no callback":
    with group = TaskGroup(timeout: 0.seconds):
        let task = group.start(
            fn() -> Int: return panic("zero timeout invoked callback")
        )

        match task.join():
            error(cause):
                match cause:
                    TimedOut:
                        return

                    _:
                        return panic("wrong timeout outcome")

            ok(_):
                return panic("zero timeout succeeded")
