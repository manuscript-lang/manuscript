import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"
import infinity, nan from "@std/math.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let count = args[1].parse_int().get()
    let expected_checksum = args[2].parse_int().get()
    let expected_last = args[3]
    let infinite = infinity()
    let not_number = nan()
    let timer = clock()
    var last = ""
    var checksum = 0
    let start = timer.now()

    if operation == "plain64":
        for i in 0..count:
            last = ((i % 1000).to_float() / 8.0).to_string()
            checksum += last.byte_length()
    else if operation == "integral64":
        for i in 0..count:
            last = (i % 1000).to_float().to_string()
            checksum += last.byte_length()
    else if operation == "scientific64":
        for i in 0..count:
            var value = 1.5e-7
            if i % 2 != 0:
                value = -1.5e-7
            last = value.to_string()
            checksum += last.byte_length()
    else if operation == "wide64":
        for i in 0..count:
            var value = 1.7976931348623157e308
            if i % 2 != 0:
                value = 5e-324
            last = value.to_string()
            checksum += last.byte_length()
    else if operation == "special64":
        for i in 0..count:
            var value = infinite
            if i % 2 != 0:
                value = not_number
            last = value.to_string()
            checksum += last.byte_length()
    else if operation == "report64":
        for i in 0..count:
            let n = i % 1000
            let value = n.to_float() / 8.0
            last = "value={value}; item={n}"
            checksum += last.byte_length()
    else:
        return 2

    let elapsed = timer.now().difference(start).to_nanoseconds()
    (
        stdout()
        .write(
            "operation={operation} count={count} ns={elapsed} checksum={checksum} last={last}\n"
        )
        .get()
    )
    if checksum != expected_checksum or last != expected_last:
        return 1

    return 0
