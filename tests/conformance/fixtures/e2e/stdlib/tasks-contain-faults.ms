# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,with-cleanup
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
    stdout().write(text + "\n")

# A fault in a contained group ends only that task: siblings keep their results.
export def main() -> Int:
    with let group = TaskGroup[Int](contain_faults: True):
        let bad = group.spawn(lambda ch: boom([1]))
        let good = group.spawn(lambda ch: 7)
        match bad.result():
            case ok(_value): say("unexpected result")
            case error(reason): say(describe(reason))
        match good.result():
            case ok(value): say(f"good {value}")
            case error(_other): say("good failed")
    with let group = TaskGroup[Int](contain_faults: True):
        group.spawn(lambda ch: boom([1]))
        match group.wait():
            case ok(_unit): say("wait ok")
            case error(reason): say(describe(reason))
    return 0
