import {TaskGroup, ExecutionError} from "@std/tasks.ms"
import panic from "@std/faults.ms"

type Summary:
    count: Int
    label: String

fn count() Int: 3

fn label() String: "ready"

fn load() Result[Summary, ExecutionError]:
    with tasks = TaskGroup():
        let count_task = tasks.start(count)
        let label_task = tasks.start(label)
        return ok(Summary(try count_task.join(), try label_task.join()))

test "load independent typed values":
    let summary = try load()
    if summary.count != 3 or summary.label != "ready":
        return panic("task values changed")
