import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn consume(parts: List[String]) Int:
    var checksum = parts.length() * 17
    for part in parts:
        checksum += part.byte_length()
    return checksum

fn split_sum(text: String, limit: Int) Int:
    if limit < 0:
        return consume(text.split(""))

    return consume(text.split("", max_parts: limit))

fn measure(name: String, text: String, expected: Int, limit: Int, iterations: Int) Int:
    if split_sum(text, limit) != expected: return 1

    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += split_sum(text, limit)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

fn input(width: Int, size: Int) String:
    if width == 1: return "x".repeat(size).get()
    if width == 3: return "é日😀".repeat(size / 9).get()

    return "😀".repeat(size / 4).get()

fn prefix_bytes(width: Int, parts: Int) Int:
    if width != 3: return parts * width

    let complete = (parts / 3) * 9
    if parts % 3 == 1: return complete + 2
    if parts % 3 == 2: return complete + 5

    return complete

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")

    for width in [1, 3, 4]:
        for size in [64, 4096, 1048576]:
            let text = input(width, size)
            let count = text.scalar_length()

            for requested in [-3, -2, -1, 0, 1, 2, 64]:
                var limit = requested
                if requested == -3: limit = count
                if requested == -2: limit = count / 2

                var parts = count
                if limit >= 0: parts = count.min(limit)

                var iterations = 4096
                if size == 64: iterations = 100000
                if size == 1048576 and width != 1: iterations = 512

                if requested < 0:
                    iterations = 1024
                    if size == 64: iterations = 100000
                    if size == 1048576: iterations = 8

                if limit == 0: iterations = 1000000
                if (
                    measure(
                        "w{width}_n{text.byte_length()}_limit{requested}", text,
                        parts * 17 + prefix_bytes(width, parts), limit, iterations
                    ) != 0
                ): return 1

    return 0
