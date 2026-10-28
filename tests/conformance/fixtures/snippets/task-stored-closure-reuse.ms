# conform: tags=diagnostics,closures,stdlib-tasks,tier-core
# conform: phase=check
from "@std/channels.ms" import Channel
from "@std/tasks.ms" import TaskGroup

def start(entry: Callable[[Channel[Unit, Unit]], Int]) -> Int:
    var group = TaskGroup[Int]()
    group.spawn(entry)
    group.spawn(entry)
    group.close()
    return 0
