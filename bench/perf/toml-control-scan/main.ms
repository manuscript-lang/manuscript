import parse, stringify from "@std/toml.ms"
import arguments from "@std/process.ms"
import filesystem from "@std/fs.ms"
import stdout from "@std/io.ms"
import clock from "@std/time.ms"

export fn main() Int:
    let args = arguments()
    let text = filesystem().read_file(args.get(0)).get().decode_utf8().get()
    let count = args.get(1).parse_int().get()
    let expected = stringify(parse(text).get()).get()

    if count == 0:
        stdout().write(expected).get()
        return 0

    var checksum = 0
    let start = clock().now()

    for unused in 0..count:
        let output = stringify(parse(text).get()).get()
        if output != expected: return 1

        checksum += output.byte_length()

    let elapsed = clock().now().difference(start).to_nanoseconds()
    stdout().write("{elapsed}\t{checksum}\t{expected.byte_length()}\n").get()
    return 0
