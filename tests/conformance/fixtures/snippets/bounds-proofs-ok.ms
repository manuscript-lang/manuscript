# conform: tags=lists,faults,perf,tier-core
# conform: phase=run
# conform: origin=range pass: relational bounds proofs
from "@std/io.ms" import stdout
from "@std/collections.ms" import range

def next_sum(a: List[Int]) -> Int:
    var t = 0
    for i in range(0, a.length() - 1):
        t = t + a[i + 1]
    return t

def mirror(a: List[Int]) -> Int:
    var b = a.clone()

    for i in range(0, b.length() / 2):
        let j = b.length() - 1 - i
        let t = b[i]
        b[i] = b[j]
        b[j] = t

    return b[0] * 100 + b[b.length() - 1]

def stride(a: List[Int]) -> Int:
    var t = 0
    for i in range(0, a.length() / 3):
        t = t + a[i * 3] + a[i * 3 + 2]
    return t

def search(a: List[Int], want: Int) -> Int:
    var lo = 0
    var hi = a.length() - 1

    while lo <= hi:
        let mid = lo + (hi - lo) / 2
        if a[mid] == want:
            return mid

        if a[mid] < want:
            lo = mid + 1
        else:
            hi = mid - 1

    return -1

def nested(g: List[List[Int]]) -> Int:
    var t = 0
    for i in range(0, g.length()):
        for j in range(0, g[i].length()):
            t = t + g[i][j]
    return t

def checked(a: List[Int], i: Int) -> Int:
    return a.get(index: i, default: -1)

export def main() -> Int:
    let a = [3, 1, 4, 1, 5, 9, 2, 6]
    stdout().write(f"{next_sum(a.clone())} {mirror(a.clone())} {stride(a.clone())}\n")
    stdout().write(
        f"{search([1, 3, 5, 7, 9, 11], 7)} {search([1, 3, 5, 7, 9, 11], 4)} {search([], 1)}\n"
    )
    stdout().write(f"{nested([[1, 2, 3], [], [4, 5]])} {nested([])}\n")
    stdout().write(
        f"{next_sum([])} {next_sum([5])} {stride([1, 2])} {checked(a.clone(), 7)}\n"
    )
    return 0
