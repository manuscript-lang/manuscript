# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,with-cleanup
# conform: phase=run
import TaskGroup from "@std/tasks.ms"

fn boom(xs: List[Int]) Int:
    return xs.get(5)

# The spawn is in main so the started-by frames are the same where the runtime can only recover
# the first generated frame (Windows): the spawn and the callers inlined into it.
export fn main() Int:
    with let group = TaskGroup[Int]():
        let task = group.spawn(fn ch: boom([1]))
        let _ = task.result()

    return 0
