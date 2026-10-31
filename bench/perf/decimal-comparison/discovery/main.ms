import from_int from "@std/math.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let n = args[1].parse_int().get()
    let count = args[2].parse_int().get()
    let timer = clock()
    var checksum = 0

    if operation == "factorial":
        var last = from_int(1)
        let modulus = from_int(1000003)
        let start = timer.now()

        for repeat in 0..count:
            var value = from_int(1)
            for i in 1..(n + 1):
                value = value * from_int(i)
            checksum += value.remainder(modulus).get().to_int().get() * (repeat % 7 + 1)
            last = value

        let elapsed = timer.now().difference(start).to_nanoseconds()
        let result = last.to_string_radix(10)
        (
            stdout()
            .write(
                "case={operation} n={n} count={count} ns={elapsed} checksum={checksum} result={result}\n"
            )
            .get()
        )
        return 0

    if operation == "lcg":
        var last = 1
        let start = timer.now()

        for repeat in 0..count:
            var value = 1
            for i in 0..n:
                value = value * 48271 % 2147483647
            checksum += value % 1000003 * (repeat % 7 + 1)
            last = value

        let elapsed = timer.now().difference(start).to_nanoseconds()
        (
            stdout()
            .write(
                "case={operation} n={n} count={count} ns={elapsed} checksum={checksum} result={last}\n"
            )
            .get()
        )
        return 0

    return 2
