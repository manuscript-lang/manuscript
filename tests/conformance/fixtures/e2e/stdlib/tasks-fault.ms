# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,scope-cleanup
# conform: phase=run
import TaskGroup from "@std/tasks.ms"

fn boom(xs: List[Int]) Int:
    return xs.get(5)

# The spawn is in main so the started-by frames are the same where the runtime can only recover
# the first generated frame (Windows): the spawn and the callers inlined into it.
export fn main() Int:
    var group = TaskGroup[Int]()
    let task = group.spawn(fn ch: boom([1]))
    let _ = task.result()
    group.close()
    return 0
