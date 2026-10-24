# conform: tags=closures,diagnostics,stdlib-processes,tier-stdlib
# conform: phase=check
from "@std/processes.ms" import ProcessGroup

export def main() -> Int:
    let base = 3
    with ProcessGroup[Int]() as group:
        let child = group.spawn(lambda ch: base)
    return 0
