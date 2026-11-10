import TomlValue, stringify from "@std/data/toml.ms"
import arguments from "@std/os/env.ms"
import read_file, write_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/time.ms"

fn encoded(text: String) String:
    var fields = Map[String, TomlValue]()
    fields.add("value", TomlValue.StringValue(text))
    return stringify(TomlValue.TableValue(fields)).get()

export fn main() Int:
    args := arguments()
    path := args.get(0)
    text := read_file(path).wait().get().decode_utf8().get()
    count := args.get(1).parse_int().get()
    expected := encoded(text)

    if count == 0:
        stdout().write(expected).get()
        return 0

    // Optional readiness marker for the external-input observability probe, outside timing.
    if args.length() > 2:
        write_file(args.get(2), "ready").wait().get()

    var checksum = 0
    start := monotonic()

    for unused in 0..count:
        current := read_file(path).wait().get().decode_utf8().get()
        output := encoded(current)
        if output != expected: return 1

        checksum += output.byte_length()

    elapsed := monotonic().difference(start).to_nanoseconds()
    print("{elapsed}\t{checksum}\t{expected.byte_length()}")
    return 0
