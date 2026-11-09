import Deque from "@std/collections/deque.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    let args = arguments()
    let n = args[0].parse_int().get()
    let count = args[1].parse_int().get()
    let repeats = args[2].parse_int().get()
    var q = Deque[Int]()
    for i in 0..n: q.push_back(i)

    let start = monotonic()
    for unused in 0..repeats: q.rotate(count)

    let ns = monotonic().difference(start).to_nanoseconds()

    if n > 0:
        let expected = ((count % n) * repeats % n + n) % n
        if q.front().get(-1) != expected or q.length() != n: return 1
    else:
        if not q.is_empty(): return 2

    print("{ns}")
    return 0
