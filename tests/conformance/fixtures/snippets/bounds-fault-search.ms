# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout

def search(a: List[Int], want: Int) -> Int:
    var lo = 0
    var hi = a.length()
    while lo <= hi:
        let mid = lo + (hi - lo) / 2
        if a[mid] == want:
            return mid
        if a[mid] < want:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1

export def main() -> Int:
    stdout().write(f"{search([1, 3, 5], 9)}\n")
    return 0
