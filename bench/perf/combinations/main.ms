import combinations from "@std/collections/itertools.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

fn main() Int:
    let args = arguments()
    let n = args[0].parse_int().get()
    let k = args[1].parse_int().get()
    let repeats = args[2].parse_int().get()
    let expected = args[3].parse_int().get()
    var input: List[Int] = []
    for i in 0..n: input.append(i)

    let start = monotonic()
    var checksum = 0

    for unused in 0..repeats:
        let output = combinations(input, k)
        if output.length() != expected: return 1

        checksum += output.length()

    print("{monotonic().difference(start).to_nanoseconds()} {checksum}")
    return 0
