# conform: tags=diagnostics,closures,stdlib-workers,tier-core
# conform: phase=check
import WorkerGroup from "@std/workers.ms"

fn work(count: Int) Unit:
    return

fn start(count: Int) Int:
    var group = WorkerGroup[Int, Int]()
    let _ = group.spawn(fn: work(count))
    group.close().get(none)
    return 0
