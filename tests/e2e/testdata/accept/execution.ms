import check_cancelled from "@std/tasks.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Optional from "@std/optional.ms"
import parallel from "@std/tasks.ms"
import parallel_map from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import Background from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import WorkStatus from "@std/tasks.ms"

fn run() -> Result[Unit, ExecutionError]:
    var offset = 3
    let first = fn() -> Int:
        return offset
    offset = 99
    let second = fn() -> Bool:
        return true
    let [number, flag] = try parallel(timeout: 1.seconds, tasks: [first, second])
    assert number == 3
    assert flag
    let operation = fn(item: Int) -> Int:
        return item * 2
    let values = try parallel_map(items: [3, 1, 2], operation: operation, limit: 2)
    assert values == [6, 2, 4]
    let [] = try parallel(tasks: [], timeout: 0.seconds)
    return ok(value: unit)

fn background_probe() -> Unit:
    with service = Background(limit: 1, drain: 2.seconds):
        let task = fn() -> Result[Unit, String]:
            return ok(value: unit)
        match service.start(operation: task):
            ok(id):
                assert true
            error(_):
                assert false
        service.close()
        match service.start(operation: task):
            ok(_):
                assert false
            error(cause):
                assert cause == StartError.Closed

test "joined work and snapshot captures":
    match run():
        ok(_):
            assert true
        error(_):
            assert false
    background_probe()


fn standard_task() -> Result[Unit, ExecutionError]:
    let [] = try parallel(tasks: [])
    let checkpoint = check_cancelled
    let [completed] = try parallel(tasks: [checkpoint])
    assert completed == unit
    return ok(value: unit)

test "closed standard function sharing proofs":
    match standard_task():
        ok(_):
            assert true
        error(_):
            assert false
