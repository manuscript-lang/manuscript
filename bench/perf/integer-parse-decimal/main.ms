import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

fn format_control(count: Int) Int:
    var checksum = 0
    let started = monotonic()

    for unused in 0..count:
        let text = (-9223372036854775808).to_string_radix(16)
        if text != "-8000000000000000": return 1

        checksum += text.byte_length()

    let elapsed = monotonic().difference(started).to_nanoseconds()
    print("ns={elapsed} checksum={checksum}")
    if checksum == 17 * count: return 0

    return 1

export fn main() Int:
    let args = arguments()
    let kind = args[0]
    let length = args[1].parse_int().get()
    let count = args[2].parse_int().get()
    if kind == "format": return format_control(count)

    let zeros = "0".repeat(length).get()
    var text = "!" + zeros
    var expected: Int? = none

    if kind == "overflow": text = "99999999999999999999" + zeros
    else if kind == "late": text = zeros + "!"
    else if kind == "zero":
        text = zeros + "1"
        expected = 1
    else if kind == "plain":
        text = "12345678"
        expected = 12345678
    else if kind == "max":
        text = "9223372036854775807"
        expected = 9223372036854775807
    else if kind == "min":
        text = "-9223372036854775808"
        expected = -9223372036854775808
    else if kind == "overflow19": text = "9223372036854775808"
    else if kind == "invalid19": text = "!000000000000000000"
    else if kind != "early": return 2

    if text.parse_int() != expected: return 1

    var checksum = 0
    let started = monotonic()

    for unused in 0..count:
        let parsed = text.parse_int()
        if parsed != expected: return 1

        checksum += parsed.get(0) % 997

    let elapsed = monotonic().difference(started).to_nanoseconds()
    print("ns={elapsed} checksum={checksum}")
    if checksum == expected.get(0) % 997 * count: return 0

    return 1
