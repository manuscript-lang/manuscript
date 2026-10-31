# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
import stdout from "@std/io.ms"

fn next_sum(a: List[Int]) Int:
    var t = 0
    for i in 0..a.length():
        t = t + a[i + 1]
    return t

export fn main() Int:
    let _ = stdout().write("{next_sum([1, 2, 3])}\n")
    return 0
