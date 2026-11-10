import (
    permutations from "@std/collections/itertools.ms",
    arguments from "@std/os/env.ms",
    monotonic from "@std/time.ms",
)

fn main() Int:
    let args = arguments()
    let n = args[0].parse_int().get()
    let size = args[1].parse_int().get()
    let repeats = args[2].parse_int().get()
    let expected = args[3].parse_int().get()
    var values: List[Int] = []
    for i in 0..n:
        values.append(i)

    let started = monotonic()
    var checksum = 0

    for unused in 0..repeats:
        let result = permutations(values, size)
        if result.length() != expected or result[0].length() != size: return 1

        checksum += result.length()

    print("{monotonic().difference(started).to_nanoseconds()} {checksum}")
    return 0
