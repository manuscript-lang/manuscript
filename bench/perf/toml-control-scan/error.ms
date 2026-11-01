import parse from "@std/data/toml.ms"
import arguments from "@std/os/process.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

fn diagnostic(text: String) String:
    match parse(text):
        ok(_): return "accepted"
        error(cause): return cause.message()

export fn main() Int:
    let args = arguments()
    let text = read_file(args.get(0)).get().decode_utf8().get()
    let count = args.get(1).parse_int().get()
    let expected = diagnostic(text)

    if count == 0:
        stdout().write(expected).get()
        return 0

    var checksum = 0
    let start = monotonic()

    for unused in 0..count:
        let output = diagnostic(text)
        if output != expected: return 1

        checksum += output.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{elapsed}\t{checksum}\t{expected.byte_length()}\n").get()
    return 0
