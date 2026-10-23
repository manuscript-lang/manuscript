# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
import {stdout} from "@std/io.ms"
import {range} from "@std/collections.ms"

fn stride(a: List[Int]) Int:
    var t = 0
    for i in range(0, a.length() / 3 + 1):
        t = t + a[i * 3 + 2]
    return t

export fn main() Int:
    stdout().write("{stride([1, 2, 3, 4, 5, 6, 7])}\n")
    return 0
