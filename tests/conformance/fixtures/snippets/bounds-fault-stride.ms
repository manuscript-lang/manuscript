# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout
from "@std/collections.ms" import range

def stride(a: List[Int]) -> Int:
    var t = 0
    for i in range(0, a.length() / 3 + 1):
        t = t + a[i * 3 + 2]
    return t

export def main() -> Int:
    let _ = stdout().write(f"{stride([1, 2, 3, 4, 5, 6, 7])}\n")
    return 0
