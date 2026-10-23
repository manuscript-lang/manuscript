# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
import {stdout} from "@std/io.ms"
import {range} from "@std/collections.ms"

fn rows(g: List[List[Int]]) Int:
    var t = 0
    for j in range(0, g[0].length()):
        t = t + g[1][j]
    return t

export fn main() Int:
    stdout().write("{rows([[1, 2, 3], [4]])}\n")
    return 0
