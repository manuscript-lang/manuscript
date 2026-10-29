# conform: tags=closures,diagnostics,stdlib-processes,tier-stdlib
# conform: phase=check
import ProcessGroup from "@std/processes.ms"

export fn main() Int:
    let base = 3
    var group = ProcessGroup[Int]()
    let child = group.spawn(fn ch: base)
    group.close()
    return 0
