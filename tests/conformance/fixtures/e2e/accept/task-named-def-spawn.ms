# conform: tags=closures,stdlib-tasks,tier-stdlib
# conform: phase=run
from "@std/channels.ms" import Channel
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup

def entry(ch: Channel[Unit, Unit]) -> Int:
    return 6

export def main() -> Int:
    with let g = TaskGroup[Int]():
        g.spawn(entry)
        g.spawn(entry)
        g.spawn(entry)
        let total = g.results().get(List[Int]())
        let _ = stdout().write("tasks " + total.length().to_string() + " first " + total[0].to_string() + "\n")
    return 0
