import arguments from "@std/process.ms"
import monotonic from "@std/time.ms"
import stdout from "@std/io.ms"
import extension, parse, normalize from "@std/fs.ms"

export fn main() Int:
    let args = arguments()
    let count = args[0].parse_int().get()
    let operation = args[1]
    let input = args[2]
    let expected_status = args[3]
    let expected_0 = args[4]
    let expected_1 = args[5]
    let expected_2 = args[6]
    let expected_3 = args[7]
    let expected_4 = args[8]
    let expected_5 = args[9]
    var checksum = 0
    var status = "OK"
    var f0 = ""
    var f1 = ""
    var f2 = ""
    var f3 = ""
    var f4 = ""
    var f5 = ""
    let started = monotonic()

    for i in 0..count:
        if operation == "extension":
            f0 = extension(input)
        else if operation == "normalize":
            f0 = normalize(input)
        else if operation == "parse":
            let value = parse(input)
            f0 = value.root
            f1 = value.directory
            f2 = value.base
            f3 = value.extension
            f4 = value.name
        else:
            return 1

        if status != expected_status:
            return 1
        if f0 != expected_0:
            return 1
        if f1 != expected_1:
            return 1
        if f2 != expected_2:
            return 1
        if f3 != expected_3:
            return 1
        if f4 != expected_4:
            return 1
        if f5 != expected_5:
            return 1

        checksum += f0.byte_length() + f1.byte_length() + f2.byte_length()
        checksum += f3.byte_length() + f4.byte_length() + f5.byte_length()
        if status == "InvalidData":
            checksum += 1

    let ns = monotonic().difference(started).to_nanoseconds()
    (
        stdout().write(
            "{count}\t{ns}\t{checksum}\t{status}\t{f0}\t{f1}\t{f2}\t{f3}\t{f4}\t{f5}\n"
        ).get()
    )
    return 0
