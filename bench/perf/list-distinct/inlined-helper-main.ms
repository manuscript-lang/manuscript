import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

fn ints(size: Int, unique: Int, repeats: Int) Int:
    var data = List[Int](reserve: size)
    for i in 0..size:
        data.append(i % unique)

    started := monotonic()
    var checksum = 0

    for unused in 0..repeats:
        result := data.distinct()
        checksum += result.length()
        for x in result:
            checksum += x

    elapsed := monotonic().difference(started).to_nanoseconds()
    print("{elapsed} {checksum}")
    return 0

fn strings(size: Int, unique: Int, repeats: Int) Int:
    var data = List[String](reserve: size)
    for i in 0..size:
        data.append("key-{i % unique}-long-enough-to-be-heap-backed")

    started := monotonic()
    var checksum = 0

    for unused in 0..repeats:
        result := data.distinct()
        checksum += result.length()
        for x in result:
            checksum += x.length()

    elapsed := monotonic().difference(started).to_nanoseconds()
    print("{elapsed} {checksum}")
    return 0

fn sets(kind: String, size: Int, shift: Int, repeats: Int) Int:
    left := Set(0..size)
    right := Set(shift..(shift + size))
    started := monotonic()
    var checksum = 0

    for unused in 0..repeats:
        result := if kind == "intersection": left.intersection(right) else: (
            if kind == "difference": left.difference(
                right
            ) else: left.symmetric_difference(right)
        )
        checksum += result.length()
        for x in result:
            checksum += x

    elapsed := monotonic().difference(started).to_nanoseconds()
    print("{elapsed} {checksum}")
    return 0

export fn main() Int:
    args := arguments()
    size := args[1].parse_int().get()
    unique := args[2].parse_int().get()
    repeats := args[3].parse_int().get()
    if args[0] == "int": return ints(size, unique, repeats)
    if args[0] == "string": return strings(size, unique, repeats)

    return sets(args[0], size, unique, repeats)
