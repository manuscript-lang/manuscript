# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,scope-cleanup
# conform: phase=run
import stdout from "@std/io/io.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"

fn boom(xs: List[Int]) Int:
    return xs.get(5)

fn describe(error: TaskError) String:
    match error:
        Faulted(report): return "faulted: " + report.split("\n").get(0)
        _: return "other error"

fn say(text: String) Unit:
    let _ = stdout().write(text + "\n")

# A fault in a contained group ends only that task: siblings keep their results.
export fn main() Int:
    var group = TaskGroup[Int](contain_faults: true)
    var bad = group.spawn(fn var ch: boom([1]))
    var good = group.spawn(fn var ch: 7)

    match bad.result():
        ok(_value): say("unexpected result")
        error(reason): say(describe(reason))

    match good.result():
        ok(value): say("good {value}")
        error(_other): say("good failed")

    group.close().get(none)

    var group2 = TaskGroup[Int](contain_faults: true)
    group2.spawn(fn var ch: boom([1]))

    match group2.wait():
        ok(_unit): say("wait ok")
        error(reason): say(describe(reason))

    group2.close().get(none)
    return 0
