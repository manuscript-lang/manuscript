# conform: tags=closures,stdlib-tasks,tier-stdlib
# conform: phase=run
import Channel from "@std/channels.ms"
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"

fn entry(ch: Channel[Unit, Unit]) Int:
    return 6

export fn main() Int:
    with let g = TaskGroup[Int]():
        g.spawn(entry)
        g.spawn(entry)
        g.spawn(entry)

        let total = g.results().get(List[Int]())
        let _ = stdout().write(
            "tasks " + total.length().to_string() + " first " + total[
                0
            ].to_string() + "\n"
        )

    return 0
