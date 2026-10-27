# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout
from "@std/collections.ms" import range

def rows(g: List[List[Int]]) -> Int:
    var t = 0
    for j in range(0, g[0].length()):
        t = t + g[1][j]
    return t

export def main() -> Int:
    let _ = stdout().write(f"{rows([[1, 2, 3], [4]])}\n")
    return 0
