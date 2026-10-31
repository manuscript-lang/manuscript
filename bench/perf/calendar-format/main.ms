import arguments from "@std/process.ms"
import timestamp, clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let count = args[0].parse_int().get()
    let pattern = args[1]
    let expected_first = args[2]
    let expected = args[3]
    let first = timestamp(1710073815, 250000000).get()
    let second = timestamp(1710073816, 250000000).get()
    let timer = clock()
    var checksum = 0
    var last = ""
    let started = timer.now()

    for i in 0..count:
        if i % 2 == 0:
            last = first.format(pattern, "UTC").get()
            if last != expected_first:
                return 1
        else:
            last = second.format(pattern, "UTC").get()
            if last != expected:
                return 1

        checksum += last.byte_length()

    let elapsed = timer.now().difference(started).to_nanoseconds()
    stdout().write("{count}\t{elapsed}\t{checksum}\t{last}\n").get()
    if checksum != expected.byte_length() * count or last != expected:
        return 1

    return 0
