import (
    parse, stringify from "@std/data/toml.ms",
    arguments from "@std/os/env.ms",
    read_file, write_file from "@std/os/fs.ms",
    stdout from "@std/io/io.ms",
    monotonic from "@std/time.ms",
)

fn main() Int:
    let args = arguments()
    let path = args[0]
    let text = read_file(path).wait().get().decode_utf8().get()
    let count = args[1].parse_int().get()
    let expected = stringify(parse(text).get()).get()

    if count == 0:
        stdout().write(expected).get()
        return 0

    // Optional readiness marker for the external-input observability probe, outside timing.
    if args.length() > 2:
        write_file(args[2], "ready").wait().get()

    var checksum = 0
    let start = monotonic()

    for unused in 0..count:
        let current = read_file(path).wait().get().decode_utf8().get()
        let output = stringify(parse(current).get()).get()
        if output != expected: return 1

        checksum += output.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    print("{elapsed}\t{checksum}\t{expected.byte_length()}")
    return 0
