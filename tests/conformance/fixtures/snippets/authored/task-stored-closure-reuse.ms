# conform: tags=diagnostics,closures,stdlib-tasks,tier-core
# conform: phase=check
import TaskChannel, TaskGroup from "@std/concurrency/tasks.ms"

fn start(entry: fn(TaskChannel[Unit, Unit]) Int) Int:
    var group = TaskGroup[Int]()
    group.spawn(entry)
    group.spawn(entry)
    group.close().get(none)
    return 0
