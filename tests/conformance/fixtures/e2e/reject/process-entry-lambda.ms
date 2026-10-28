# conform: tags=closures,diagnostics,stdlib-processes,tier-stdlib
# conform: phase=check
from "@std/processes.ms" import ProcessGroup

export def main() -> Int:
    let base = 3
    var group = ProcessGroup[Int]()
    let child = group.spawn(lambda ch: base)
    group.close()
    return 0
