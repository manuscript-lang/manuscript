import parse, stringify from "@std/toml.ms"
import arguments from "@std/process.ms"
import read_file, write_file from "@std/fs.ms"
import stdout from "@std/io.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    let args = arguments()
    let path = args.get(0)
    let text = read_file(path).get().decode_utf8().get()
    let count = args.get(1).parse_int().get()
    let expected = stringify(parse(text).get()).get()

    if count == 0:
        stdout().write(expected).get()
        return 0

    # Optional readiness marker for the external-input observability probe, outside timing.
    if args.length() > 2:
        write_file(args.get(2), "ready").get()

    var checksum = 0
    let start = monotonic()

    for unused in 0..count:
        let current = read_file(path).get().decode_utf8().get()
        let output = stringify(parse(current).get()).get()
        if output != expected: return 1

        checksum += output.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{elapsed}\t{checksum}\t{expected.byte_length()}\n").get()
    return 0
