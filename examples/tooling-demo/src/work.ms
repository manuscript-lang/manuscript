import {TaskGroup, ExecutionError} from "@std/tasks.ms"
import range from "@std/collections.ms"

fn compute() Int:
    var result = 0
    for index in range(0, 3000000):
        result += index % 7
    return result

fn compare() Result[Int, ExecutionError]:
    with group = TaskGroup():
        let first = group.start(compute)
        let second = group.start(compute)
        let left = try first.join()
        let right = try second.join()
        if left != right:
            return ok(1)

        return ok(0)

export fn main() Int:
    if let code = compare():
        return code

    return 1
