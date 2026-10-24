# conform: tags=closures,faults,stdlib-tasks,tier-stdlib,with-cleanup
# conform: phase=run
from "@std/tasks.ms" import TaskGroup

def boom(xs: List[Int]) -> Int:
    return xs.get(5)

def load() -> Int:
    with TaskGroup[Int]() as group:
        let task = group.spawn(lambda ch: boom([1]))
        task.result()
    return 0

export def main() -> Int:
    return load()
