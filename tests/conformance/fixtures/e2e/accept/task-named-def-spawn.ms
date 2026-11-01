# conform: tags=closures,stdlib-tasks,tier-stdlib
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"

fn entry(var ch: Channel[Unit, Unit]) Int:
    return 6

export fn main() Int:
    var g = TaskGroup[Int]()
    g.spawn(entry)
    g.spawn(entry)
    g.spawn(entry)

    let total = g.results().get(List[Int]())
    let _ = stdout().write(
        "tasks " + total.length().to_string() + " first " + total[
            0
        ].to_string() + "\n"
    )
    g.close().get(none)
    return 0
