from "@std/collections.ms" import range
from "@std/io.ms" import stdout
from "@std/string.ms" import StringBuilder
from "@std/time.ms" import clock

# Builds a about 1 MB string from pieces of each size and prints the best of 40 runs per size in microseconds.
def run(piece: String, count: Int) -> Int:
    var sb = StringBuilder()
    for i in range(0, count):
        sb.append(piece)
    return sb.build().byte_length()

# Builds a list of `count` Ints with append in a `while` loop, so growth is by doubling, the path every list shares with the builder.
def fill(count: Int) -> Int:
    var items: List[Int] = []
    var i = 0

    while i < count:
        items.append(i)
        i += 1

    return items.length()

export def main() -> Int:
    var piece = "x"

    for size in [4, 16, 64, 256, 1024, 8192]:
        piece = "x".repeat(size).get()

        let count = 1000000 / size
        var best = 1000000000000
        var checksum = 0

        for rep in range(0, 40):
            let started = clock().now()
            checksum += run(piece, count)

            let elapsed = clock().now().difference(started).to_nanoseconds()
            if elapsed < best:
                best = elapsed

        let _ignored = stdout().write(f"append{size}\t{best / 1000}\t# {checksum}\n")

    for count in [10000, 100000, 1000000]:
        var best = 1000000000000
        var checksum = 0

        for rep in range(0, 40):
            let started = clock().now()
            checksum += fill(count)

            let elapsed = clock().now().difference(started).to_nanoseconds()
            if elapsed < best:
                best = elapsed

        let _ignored = stdout().write(f"list{count}\t{best / 1000}\t# {checksum}\n")

    return 0
