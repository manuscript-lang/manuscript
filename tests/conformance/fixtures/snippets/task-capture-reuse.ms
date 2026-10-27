# conform: tags=closures,stdlib-tasks,tier-core
# conform: phase=run
# conform: origin=foreign-syntax diagnostics
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup

def show(xs: List[Int]) -> Int:
    with let group = TaskGroup[Int]():
        group.spawn(lambda ch: xs.length())
        group.spawn(lambda ch: xs.length())
    return 0

export def main() -> Int:
    stdout().write(f"{show([1, 2, 3])}\n").get()
    return 0
