import arguments from "@std/os/process.ms"
import monotonic from "@std/os/time.ms"
import stdout from "@std/io/io.ms"
import parse_int from "@std/math/math.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let dataset = args[1]
    let digits = args[2].parse_int().get()
    let count = args[3].parse_int().get()
    let expected_checksum = args[4].parse_int().get()
    let expected_last = args[5]

    if operation == "parse_zero":
        let zeros = "0".repeat(4096).get()
        let text = "{zeros}1"
        var checksum = 0
        var last = 0
        let start = monotonic()

        for unused in 0..count:
            last = parse_int(text, digits).get()
            checksum += last

        let elapsed = monotonic().difference(start).to_nanoseconds()
        let final_text = last.to_string()
        stdout().write("ns={elapsed} checksum={checksum} last={final_text}\n").get()
        if checksum != expected_checksum or final_text != expected_last:
            return 1

        return 0

    if operation == "parse_error":
        var length = 4096
        if dataset == "overflow-short":
            length = 32

        var text = (digits - 1).to_string_radix(digits).repeat(length).get()

        if dataset == "late":
            text = "{text}!"
        else if dataset == "early":
            text = "!{text}"

        var checksum = 0
        var last = ""
        let start = monotonic()

        for unused in 0..count:
            last = parse_int(text, digits).err().message()
            checksum += last.byte_length()

        let elapsed = monotonic().difference(start).to_nanoseconds()
        stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
        if checksum != expected_checksum or last != expected_last:
            return 1

        return 0

    if operation == "parse":
        var texts = List[String](reserve: 1000)

        for i in 0..1000:
            var value = i

            if dataset == "wide":
                value = 9223372036800000000 + i
            else if dataset == "negative":
                value = -9223372036854775808 + i

            texts.append(value.to_string_radix(digits))
            if parse_int(texts[i], digits).get() != value:
                return 1

        var checksum = 0
        var last = 0
        let start = monotonic()

        for i in 0..count:
            last = parse_int(texts[i % 1000], digits).get()
            checksum += last % 997

        let elapsed = monotonic().difference(start).to_nanoseconds()
        let final_text = last.to_string()
        stdout().write("ns={elapsed} checksum={checksum} last={final_text}\n").get()
        if checksum != expected_checksum or final_text != expected_last:
            return 1

        return 0

    var last = ""
    var checksum = 0
    let start = monotonic()

    for i in 0..count:
        var value = (i % 1000).to_float() / 8.0

        if dataset == "wide":
            value = 1.7976931348623157e308
            if i % 2 != 0:
                value = 5e-324
        else if dataset == "zero":
            value = 0.0
            if i % 2 != 0:
                value = -0.0

        if operation == "exponential":
            last = value.to_exponential(digits)
        else if operation == "precision":
            last = value.to_precision(digits)
        else if operation == "fixed":
            last = value.to_fixed(digits)
        else if operation == "shortest":
            last = value.to_string()
        else:
            return 2

        checksum += last.byte_length()

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
    if checksum != expected_checksum or last != expected_last:
        return 1

    return 0
