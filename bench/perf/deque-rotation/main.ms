import Deque from "@std/collections/deque.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    args := arguments()
    n := args[0].parse_int().get()
    count := args[1].parse_int().get()
    repeats := args[2].parse_int().get()
    var q = Deque[Int]()
    for i in 0..n: q.push_back(i)

    start := monotonic()
    for unused in 0..repeats: q.rotate(count)

    ns := monotonic().difference(start).to_nanoseconds()

    if n > 0:
        expected := ((count % n) * repeats % n + n) % n
        if q.front().get(-1) != expected or q.length() != n: return 1
    else:
        if not q.is_empty(): return 2

    print("{ns}")
    return 0
