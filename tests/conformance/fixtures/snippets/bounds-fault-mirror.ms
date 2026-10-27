# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout

def mirror(a: List[Int]) -> Int:
    var t = 0
    for i in 0..a.length() / 2:
        t = t + a[a.length() - i]
    return t

export def main() -> Int:
    let _ = stdout().write(f"{mirror([1, 2, 3, 4])}\n")
    return 0
