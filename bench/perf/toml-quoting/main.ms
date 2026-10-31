import TomlValue, stringify from "@std/toml.ms"
import arguments from "@std/process.ms"
import read_file from "@std/fs.ms"
import stdout from "@std/io.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    let args = arguments()
    let text = read_file(args.get(0)).get().decode_utf8().get()
    let count = args.get(1).parse_int().get()
    var fields = Map[String, TomlValue]()
    fields.add("value", TomlValue.StringValue(text))

    let value = TomlValue.TableValue(fields)
    let expected = stringify(value).get()

    if count == 0:
        stdout().write(expected).get()
        return 0

    var checksum = 0
    let start = monotonic()

    for unused in 0..count:
        let out = stringify(value).get()
        if out != expected: return 1

        checksum += out.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{elapsed}\t{checksum}\t{expected.byte_length()}\n").get()
    return 0
