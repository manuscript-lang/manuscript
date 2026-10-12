import List from "@std/collections.ms"
import parallel from "@std/tasks.ms"

fn compute() -> Int:
    var index = 0
    var result = 0
    while index < 3000000:
        result = result + index % 7
        index = index + 1
    return result

export fn main() -> Int:
    let first = fn() -> Int:
        return compute()
    let second = fn() -> Int:
        return compute()
    match parallel(tasks: [first, second]):
        ok(values):
            let [left, right] = values
            if left != right:
                return 1
            return 0
        error(_):
            return 1
