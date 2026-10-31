import stdout from "@std/io.ms"
import arguments from "@std/process.ms"
import monotonic from "@std/time.ms"

fn ints(size: Int, unique: Int, repeats: Int) Int:
    var data = List[Int](reserve: size)
    for i in 0..size:
        data.append(i % unique)

    let started = monotonic()
    var checksum = 0

    for unused in 0..repeats:
        let result = data.distinct()
        checksum += result.length()
        for x in result:
            checksum += x

    let elapsed = monotonic().difference(started).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0

fn strings(size: Int, unique: Int, repeats: Int) Int:
    var data = List[String](reserve: size)
    for i in 0..size:
        data.append("key-{i % unique}-long-enough-to-be-heap-backed")

    let started = monotonic()
    var checksum = 0

    for unused in 0..repeats:
        let result = data.distinct()
        checksum += result.length()
        for x in result:
            checksum += x.length()

    let elapsed = monotonic().difference(started).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0

fn sets(kind: String, size: Int, shift: Int, repeats: Int) Int:
    let left = Set(0..size)
    let right = Set(shift..(shift + size))
    let started = monotonic()
    var checksum = 0

    for unused in 0..repeats:
        let result = if kind == "intersection": left.intersection(right) else: (
            if kind == "difference": left.difference(
                right
            ) else: left.symmetric_difference(right)
        )

        checksum += result.length()
        for x in result:
            checksum += x

    let elapsed = monotonic().difference(started).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0

export fn main() Int:
    let args = arguments()
    let size = args[1].parse_int().get()
    let unique = args[2].parse_int().get()
    let repeats = args[3].parse_int().get()
    if args[0] == "int":
        return ints(size, unique, repeats)
    if args[0] == "string":
        return strings(size, unique, repeats)

    return sets(args[0], size, unique, repeats)
