# conform: tags=diagnostics,closures,stdlib-workers,tier-core
# conform: phase=check
from "@std/workers.ms" import WorkerGroup

def work(count: Int) -> Unit:
    return

def start(count: Int) -> Int:
    with WorkerGroup[Int, Int]() as group:
        group.spawn(lambda: work(count))
    return 0
