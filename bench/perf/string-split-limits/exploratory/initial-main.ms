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

fn input(width: Int, count: Int) String:
    if width == 1: return "x".repeat(count).get()

    return "😀".repeat(count).get()

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")

    for width in [1, 4]:
        for size in [64, 4096, 1048576]:
            let count = size / width
            let text = input(width, count)

            for limit in [-1, 0, 1, 2, 64]:
                var parts = count
                if limit >= 0: parts = count.min(limit)

                var iterations = 4096
                if size == 64: iterations = 100000

                if limit < 0:
                    iterations = 64
                    if size == 1048576: iterations = 8

                if (
                    measure(
                        "w{width}_n{size}_limit{limit}", text, parts * (17 + width),
                        limit, iterations
                    ) != 0
                ): return 1

    return 0
