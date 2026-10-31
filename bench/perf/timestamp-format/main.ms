import arguments from "@std/process.ms"
import timestamp, clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let count = args[0].parse_int().get()
    let first = timestamp(args[1].parse_int().get(), args[2].parse_int().get()).get()
    let second = timestamp(args[3].parse_int().get(), args[4].parse_int().get()).get()
    let expected_first = args[5]
    let expected_second = args[6]
    let timer = clock()
    var checksum = 0
    var last = ""
    let started = timer.now()

    for i in 0..count:
        if i % 2 == 0:
            last = first.to_string()
            if last != expected_first:
                return 1
        else:
            last = second.to_string()
            if last != expected_second:
                return 1

        checksum += last.byte_length()

    let ns = timer.now().difference(started).to_nanoseconds()
    stdout().write("{count}\t{ns}\t{checksum}\t{last}\n").get()
    if (
        checksum != count / 2 * (
            expected_first.byte_length()
            + expected_second.byte_length()
        )
    ):
        return 1

    return 0
