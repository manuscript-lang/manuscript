import {TaskGroup, ExecutionError} from "@std/tasks.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"

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
            if summary.count != 3 or summary.label != "ready":
                return panic("task values changed")

        error(_):
            return panic("task group failed")
