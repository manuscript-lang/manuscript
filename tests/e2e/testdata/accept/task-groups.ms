import {TaskGroup, Task, ExecutionError} from "@std/tasks.ms"
import Closeable from "@std/cleanup.ms"
import panic from "@std/faults.ms"

type Stored:
    task: Task[Int]

fn forward[T](task: Task[T]) Task[T]:
    return task

fn exercise() Result[Unit, ExecutionError]:
    with group = TaskGroup():
        let start = group.start[Int]
        let number: Task[Int] = start(fn(): 41)
        let text = group.start(fn(): "hello")
        let domain = group.start(fn() Result[Int, String]: error("expected"))
        let stored = Stored(forward(number))
        let handles: List[Task[Int]] = [stored.task]
        try group.join()
        try group.join()
        let value = try stored.task.join()
        let value_again = try number.join()
        let message = try text.join()
        if (value != 41 or value_again != 41 or message != "hello"):
            return panic("typed results changed")

        for handle in handles:
            let saved_join: fn() Result[Int, ExecutionError] = handle.join
            let saved_value = try saved_join()
            if saved_value != 41:
                return panic("saved task join changed")

        let outcome = try domain.join()
        if outcome.is_ok():
            return panic("domain error flattened")
        if outcome.unwrap_error() != "expected":
            return panic("domain error changed")

        let resource = Closeable(group)
        resource.close()
        let after_close = try number.join()
        if after_close != 41:
            return panic("close erased result")

    with group = TaskGroup():
        let value = try group.start(fn(): 1).join()
        let following = try group.start(fn(): value + 1).join()
        if following != 2:
            return panic("individual join sealed group")

    return ok(unit)

test "typed tasks group joins and cached outcomes":
    try exercise()

test "empty group joins and closes repeatedly":
    with group = TaskGroup(0.seconds):
        try group.join()
        group.close()
        group.close()

test "zero timeout starts no callback":
    with group = TaskGroup(0.seconds):
        let task = group.start(fn(): panic("zero timeout invoked callback"))
        let joined = task.join()
        if joined.is_ok():
            return panic("zero timeout succeeded")

        let cause = joined.unwrap_error()

        match cause:
            Timeout:
                return
            _:
                return panic("wrong timeout outcome")
