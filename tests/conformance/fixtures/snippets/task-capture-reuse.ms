# conform: tags=diagnostics,closures,stdlib-tasks,tier-core
# conform: phase=check
# conform: origin=foreign-syntax diagnostics
from "@std/tasks.ms" import TaskGroup

def show(xs: List[Int]) -> Int:
    with TaskGroup[Int]() as group:
        group.spawn(lambda ch: xs.length())
        group.spawn(lambda ch: xs.length())
    return 0
