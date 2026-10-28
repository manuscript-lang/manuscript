# conform: tags=closures,stdlib-tasks,tier-core
# conform: phase=run
# conform: origin=foreign-syntax diagnostics
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"

fn show(xs: List[Int]) Int:
    with let group = TaskGroup[Int]():
        group.spawn(fn ch: xs.length())
        group.spawn(fn ch: xs.length())

    return 0

export fn main() Int:
    stdout().write("{show([1, 2, 3])}\n").get()
    return 0
