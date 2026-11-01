import parse from "@std/data/json.ms"
import base64_encode from "@std/data/encoding.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

export fn main() Int:
    let args = arguments()
    let length = args[0].parse_int().get()
    let count = args[1].parse_int().get()
    let rounds = args[2].parse_int().get()
    var bytes = BytesBuilder()
    for i in 0..length: bytes.append((i % 256).to_uint8().get())

    let expected = bytes.build()
    let encoded = base64_encode(expected)
    var json = StringBuilder()
    json.append("[")

    for i in 0..count:
        if i > 0: json.append(",")
        json.append("\"{encoded}\"")

    json.append("]")

    let text = json.build()
    var checksum = 0
    let start = monotonic()

    for i in 0..rounds:
        let result = parse[List[Bytes]](text)
        if result.is_error(): return 2

        let values = result.get()
        if values.length() != count: return 3

        for value in values:
            if value != expected: return 4

            checksum += value.length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{length} {count} {rounds} {checksum} {elapsed}\n").get()
    return 0
