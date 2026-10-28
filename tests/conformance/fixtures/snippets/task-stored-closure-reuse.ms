# conform: tags=diagnostics,closures,stdlib-tasks,tier-core
# conform: phase=check
import Channel from "@std/channels.ms"
import TaskGroup from "@std/tasks.ms"

fn start(entry: fn(Channel[Unit, Unit]) Int) Int:
    with let group = TaskGroup[Int]():
        group.spawn(entry)
        group.spawn(entry)

    return 0
