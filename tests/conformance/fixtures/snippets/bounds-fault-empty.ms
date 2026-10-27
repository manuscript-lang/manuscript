# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout
from "@std/collections.ms" import range

def last_after_loop(a: List[Int]) -> Int:
    var t = 0
    for i in range(0, a.length()):
        t = t + a[i]
    return t + a[a.length() - 1]

export def main() -> Int:
    let _ = stdout().write(f"{last_after_loop([])}\n")
    return 0
