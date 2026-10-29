import BitSet from "@std/bitset.ms"
import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"

export fn main() Int:
    let args = arguments()
    let kind = args[0]
    let size = args[1].parse_int().get()
    let pattern = args[2]
    let repeats = args[3].parse_int().get()
    var left = BitSet()
    var right = BitSet()

    for i in 0..size:
        left.words.append(if kind == "disjoint": -1 else: 0)
        right.words.append(if kind == "disjoint": 0 else: -1)

    if size > 0 and pattern != "true":
        let index = if pattern == "early": 0 else: size - 1

        left.words.set(index, -1)
        right.words.set(index, if kind == "disjoint": -1 else: 0)

    let started = clock().now()
    var checksum = 0

    for unused in 0..repeats:
        let result = if kind == "subset": left.is_subset_of(right) else: (
            if kind == "superset": right.is_superset_of(
                left
            ) else: left.is_disjoint_from(right)
        )

        if result:
            checksum += 1

    let elapsed = clock().now().difference(started).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0
