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

export fn main() Int:
    args := arguments()
    size := args[1].parse_int().get()
    unique := args[2].parse_int().get()
    repeats := args[3].parse_int().get()
    if args[0] == "int": return ints(size, unique, repeats)

    return strings(size, unique, repeats)
