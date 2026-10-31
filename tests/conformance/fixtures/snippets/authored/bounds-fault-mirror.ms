# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
import stdout from "@std/io.ms"

fn mirror(a: List[Int]) Int:
    var t = 0
    for i in 0..a.length() / 2:
        t = t + a[a.length() - i]
    return t

export fn main() Int:
    let _ = stdout().write("{mirror([1, 2, 3, 4])}\n")
    return 0
