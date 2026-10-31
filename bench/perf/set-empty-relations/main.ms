import arguments from "@std/process.ms"
import monotonic from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let mode = args[0]
    let size = args[1].parse_int().get()
    let repeats = args[2].parse_int().get()
    let pattern = args[3]
    var left = Set[Int]()
    var right = Set[Int]()

    for i in 0..size:
        if pattern != "empty-left":
            left.add(i)

        if pattern != "empty-right":
            if pattern == "disjoint":
                right.add(i + size)
            else if pattern == "small-right":
                if i == 0:
                    right.add(size)
            else if pattern == "early":
                right.add(if i == 0: size else: i)
            else if pattern == "late":
                right.add(if i == size - 1: size else: i)
            else:
                right.add(i)

    let start = monotonic()
    var checksum = 0

    for iteration in 0..repeats:
        let answer = if mode == "subset": left.is_subset_of(right) else: (
            if mode == "superset": left.is_superset_of(
                right
            ) else: left.is_disjoint_from(right)
        )

        if answer:
            checksum += 1

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0
