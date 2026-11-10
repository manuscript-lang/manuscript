import TomlValue, stringify from "@std/data/toml.ms"
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    args := arguments()
    text := read_file(args.get(0)).wait().get().decode_utf8().get()
    count := args.get(1).parse_int().get()
    var fields = Map[String, TomlValue]()
    fields.add("value", TomlValue.StringValue(text))

    value := TomlValue.TableValue(fields)
    expected := stringify(value).get()

    if count == 0:
        stdout().write(expected).get()
        return 0

    var checksum = 0
    start := monotonic()

    for unused in 0..count:
        out := stringify(value).get()
        if out != expected: return 1

        checksum += out.byte_length()

    elapsed := monotonic().difference(start).to_nanoseconds()
    print("{elapsed}\t{checksum}\t{expected.byte_length()}")
    return 0
