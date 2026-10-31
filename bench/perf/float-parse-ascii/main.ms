import arguments from "@std/process.ms"
import monotonic from "@std/time.ms"
import stdout from "@std/io.ms"
import infinity, nan from "@std/math.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let dataset = args[1]
    let count = args[3].parse_int().get()
    let expected_checksum = args[4].parse_int().get()
    let expected_last = args[5]
    var checksum = 0
    var last = ""

    if operation == "signed" or operation == "parse_int":
        var values = List[Int](reserve: 1000)
        var texts = List[String](reserve: 1000)

        for i in 0..1000:
            var value = i

            if dataset == "wide":
                value = 9223372036800000000 + i
            else if dataset == "negative":
                value = -9223372036854775808 + i

            values.append(value)
            texts.append(value.to_string())
            if texts[i].parse_int().get() != value:
                return 1

        if operation == "signed":
            let start = monotonic()

            for i in 0..count:
                last = values[i % 1000].to_string()
                checksum += last.byte_length()

            let elapsed = monotonic().difference(start).to_nanoseconds()
            stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
        else:
            var value = 0
            let start = monotonic()

            for i in 0..count:
                value = texts[i % 1000].parse_int().get()
                checksum += value % 997

            let elapsed = monotonic().difference(start).to_nanoseconds()
            last = value.to_string()
            stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
    else if operation == "parse_float":
        var texts = List[String]()
        var values = List[Float]()

        if dataset == "long":
            let zeros = "0".repeat(4096).get()
            texts = ["0.{zeros}1"]
            values = [0.0]
        else if dataset == "wide":
            texts = ["1.7976931348623157e308", "5e-324", "1e20", "-1e20", "-0", "0"]
            values = [1.7976931348623157e308, 5e-324, 1e20, -1e20, -0.0, 0.0]
        else if dataset == "scientific":
            texts = ["1.5e-7", "-1.5e-7"]
            values = [1.5e-7, -1.5e-7]
        else:
            for i in 0..1000:
                let value = i.to_float() / 8.0
                values.append(value)
                texts.append(value.to_string())

        for i in 0..texts.length():
            let actual = texts[i].parse_float().get()
            if actual != values[i] or actual.to_string() != values[i].to_string():
                return 1

        let length = texts.length()
        let start = monotonic()

        for i in 0..count:
            let index = i % length
            let actual = texts[index].parse_float().get()
            if actual == values[index]:
                checksum += 1

        let elapsed = monotonic().difference(start).to_nanoseconds()
        last = "ok"
        stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
    else if operation == "float_special":
        let texts = ["Infinity", "-Infinity", "NaN"]
        let values = [infinity(), -infinity(), nan()]
        let start = monotonic()

        for i in 0..count:
            let index = i % 3
            let actual = texts[index].parse_float().get()

            if index == 2:
                if actual.is_nan():
                    checksum += 1
            else if actual == values[index]:
                checksum += 1

        let elapsed = monotonic().difference(start).to_nanoseconds()
        last = "ok"
        stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
    else if operation == "float_error":
        var text = "!"

        if dataset == "late":
            let digits = "9".repeat(4096).get()
            text = "{digits}!"
        else if dataset == "range":
            text = "1e400"
        else if dataset == "range-long":
            text = "9".repeat(4096).get()
        else if dataset == "unicode":
            text = "١"

        if not text.parse_float().is_none():
            return 1

        let start = monotonic()
        for unused in 0..count:
            if text.parse_float().is_none():
                checksum += 1

        let elapsed = monotonic().difference(start).to_nanoseconds()
        last = "none"
        stdout().write("ns={elapsed} checksum={checksum} last={last}\n").get()
    else:
        return 2

    if checksum != expected_checksum or last != expected_last:
        return 1

    return 0
