# conform: tags=closures,stdlib-tasks,tier-core
# conform: phase=run
# conform: origin=foreign-syntax diagnostics
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"

fn show(xs: List[Int]) Int:
    var group = TaskGroup[Int]()

    # Each task owns its capture, and `xs` is only borrowed, so each one takes a clone.
    let first = xs.clone()
    group.spawn(fn var ch: first.length())

    let second = xs.clone()
    group.spawn(fn var ch: second.length())
    group.close().get(none)
    return 0

export fn main() Int:
    stdout().write("{show([1, 2, 3])}\n").get()
    return 0
