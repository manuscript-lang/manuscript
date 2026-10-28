# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,scope-cleanup
# conform: phase=run
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskError, TaskGroup

def boom(xs: List[Int]) -> Int:
    return xs.get(5)

def describe(error: TaskError) -> String:
    match error:
        case Faulted(report): return "faulted: " + report.split("\n").get(0)
        case _: return "other error"

def say(text: String) -> Unit:
    let _ = stdout().write(text + "\n")

# A fault in a contained group ends only that task: siblings keep their results.
export def main() -> Int:
    var group = TaskGroup[Int](contain_faults: True)
    let bad = group.spawn(lambda ch: boom([1]))
    let good = group.spawn(lambda ch: 7)

    match bad.result():
        case ok(_value): say("unexpected result")
        case error(reason): say(describe(reason))

    match good.result():
        case ok(value): say(f"good {value}")
        case error(_other): say("good failed")

    group.close()

    var group2 = TaskGroup[Int](contain_faults: True)
    group2.spawn(lambda ch: boom([1]))

    match group2.wait():
        case ok(_unit): say("wait ok")
        case error(reason): say(describe(reason))

    group2.close()
    return 0
