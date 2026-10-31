import Bytes from "@std/bytes.ms"
import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn measure(name: String, data: Bytes, start: Int, expected: Int, iterations: Int) Int:
    if data.index_of_byte(255, start).get(data.length()) != expected: return 1

    var checksum = 0
    let started = clock().now()
    for unused in 0..iterations:
        checksum += data.index_of_byte(255, start).get(data.length())

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected * iterations: return 1

    let _written = stdout().write(
        "{name},{data.length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")

    for n in [0, 1, 7, 15, 31, 32, 64, 256, 4096, 1048576]:
        for kind in [
            "miss", "first", "middle", "last", "negative", "past", "equal", "offset",
            "near1", "near7", "near15", "near16", "near17"
        ]:
            var data = "a".repeat(n).get().to_bytes()
            var pos = -1
            var start = 0
            if kind == "first" or kind == "negative" or kind == "past": pos = 0
            if kind == "near1": pos = 1
            if kind == "near7": pos = 7
            if kind == "near15": pos = 15
            if kind == "near16": pos = 16
            if kind == "near17": pos = 17
            if kind.starts_with("near") and pos >= n: pos = n - 1
            if kind == "middle": pos = n / 2
            if kind == "last" or kind == "offset": pos = n - 1
            if kind == "negative": start = -1
            if kind == "past": start = n + 1
            if kind == "equal": start = n
            if kind == "offset": start = n / 2
            if pos >= 0 and pos < n: data = data.with_value(pos, 255)

            var expected = n
            if pos >= 0 and pos < n and start <= pos: expected = pos

            var work = n
            if expected < n: work = expected + 1 - start
            if start < 0: work = expected + 1
            if start >= n: work = 1
            if work < 32: work = 32

            var iterations = 67108864 / work
            if iterations < 256: iterations = 256
            if iterations > 1000000: iterations = 1000000
            if measure("{kind}_{n}", data, start, expected, iterations) != 0: return 1

    return 0
