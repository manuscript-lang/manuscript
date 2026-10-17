import TaskGroup from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"

fn compute() -> Int:
    var index = 0
    var result = 0

    while index < 3000000:
        result = result + index % 7
        index = index + 1

    return result

fn compare() -> Result[Int, ExecutionError]:
    with group = TaskGroup():
        let first = group.start(compute)
        let second = group.start(compute)
        let left = try first.join()
        let right = try second.join()
        if left != right:
            return ok(1)

        return ok(0)

export fn main() -> Int:
    if let code = compare():
        return code

    return 1
