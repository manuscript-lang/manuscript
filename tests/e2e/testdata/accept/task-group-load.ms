import {expect_false, fail} from "@std/testing.ms"
import {TaskGroup, ExecutionError} from "@std/tasks.ms"

type Summary:
    count: Int
    label: String

fn count() -> Int: 3

fn label() -> String: "ready"

fn load() -> Result[Summary, ExecutionError]:
    with tasks = TaskGroup():
        let count_task = tasks.start(count)
        let label_task = tasks.start(label)
        return ok(Summary(count: try count_task.join(), label: try label_task.join()))

test "load independent typed values":
    match load():
        ok(summary):
            ((summary.count != 3 or summary.label != "ready") | try expect_false)
        error(_):
            return fail("task group failed")
