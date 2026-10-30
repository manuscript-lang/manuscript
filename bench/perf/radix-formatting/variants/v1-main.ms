import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let radix = args[1].parse_int().get()
    let count = args[2].parse_int().get()
    let expected_checksum = args[3].parse_int().get()
    let expected_last = args[4]
    let maximum: UInt64 = 18446744073709551615
    let minimum: Int = -9223372036854775808
    let timer = clock()
    var checksum = 0
    var last = ""
    let start = timer.now()

    if operation == "signed-wide":
        for i in 0..count:
            last = (9223372036800000000 + i % 1000).to_string_radix(radix)
            checksum += last.byte_length()
    else if operation == "negative-wide":
        for i in 0..count:
            last = (minimum + i % 1000).to_string_radix(radix)
            checksum += last.byte_length()
    else if operation == "unsigned-wide":
        for i in 0..count:
            last = (maximum - (i % 1000).to_uint64().get()).to_string_radix(radix)
            checksum += last.byte_length()
    else if operation == "signed-small":
        for i in 0..count:
            last = (i % 1000).to_string_radix(radix)
            checksum += last.byte_length()
    else if operation == "zero":
        for i in 0..count:
            last = 0.to_string_radix(radix)
            checksum += last.byte_length()
    else if operation == "decimal-control":
        for i in 0..count:
            last = (9223372036800000000 + i % 1000).to_string()
            checksum += last.byte_length()
    else:
        return 2

    let elapsed = timer.now().difference(start).to_nanoseconds()
    (
        stdout()
        .write(
            "operation={operation} radix={radix} count={count} ns={elapsed} checksum={checksum} last={last}\n"
        )
        .get()
    )
    if checksum != expected_checksum or last != expected_last:
        return 1

    return 0
