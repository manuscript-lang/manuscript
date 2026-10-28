# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,scope-cleanup
# conform: phase=run
from "@std/tasks.ms" import TaskGroup

def boom(xs: List[Int]) -> Int:
    return xs.get(5)

# The spawn is in main so the started-by frames are the same where the runtime can only recover
# the first generated frame (Windows): the spawn and the callers inlined into it.
export def main() -> Int:
    var group = TaskGroup[Int]()
    let task = group.spawn(lambda ch: boom([1]))
    let _ = task.result()
    group.close()
    return 0
