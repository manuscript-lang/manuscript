import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    args := arguments()
    mode := args[0]
    size := args[1].parse_int().get()
    repeats := args[2].parse_int().get()
    pattern := args[3]
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

    start := monotonic()
    var checksum = 0

    for iteration in 0..repeats:
        answer := if mode == "subset": left.is_subset_of(right) else: (
            if mode == "superset": left.is_superset_of(
                right
            ) else: left.is_disjoint_from(right)
        )
        if answer:
            checksum += 1

    elapsed := monotonic().difference(start).to_nanoseconds()
    print("{elapsed} {checksum}")
    return 0
