import permutations from "@std/collections/itertools.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    args := arguments()
    n := args[0].parse_int().get()
    size := args[1].parse_int().get()
    repeats := args[2].parse_int().get()
    expected := args[3].parse_int().get()
    var values: List[Int] = []
    for i in 0..n:
        values.append(i)

    started := monotonic()
    var checksum = 0

    for unused in 0..repeats:
        result := permutations(values, size)
        if result.length() != expected or result[0].length() != size: return 1

        checksum += result.length()

    print("{monotonic().difference(started).to_nanoseconds()} {checksum}")
    return 0
