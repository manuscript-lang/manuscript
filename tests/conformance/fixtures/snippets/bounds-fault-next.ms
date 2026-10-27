# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout
from "@std/collections.ms" import range

def next_sum(a: List[Int]) -> Int:
    var t = 0
    for i in range(0, a.length()):
        t = t + a[i + 1]
    return t

export def main() -> Int:
    let _ = stdout().write(f"{next_sum([1, 2, 3])}\n")
    return 0
