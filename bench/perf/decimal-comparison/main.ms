import Decimal from "@std/decimal.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let name = args[0]
    let count = args[1].parse_int().get()
    var left: List[Decimal] = []
    var right: List[Decimal] = []
    var expected: List[Int] = []

    if name == "common":
        left = [
            0d, 1d, -1d, 123456789d, -123456789d, 9223372036854775807d,
            -9223372036854775808d, 1d
        ]
        right = [
            1d, 0d, 1d, 123456788d, -123456788d, 9223372036854775806d,
            -9223372036854775807d, 1d
        ]
        expected = [-1, 1, -1, 1, -1, 1, -1, 0]
    else if name == "signs":
        left = [1e-6176d, -1e-6176d, 0d, -1e-6176d, 1e6144d, 0d, 0d, -1d]
        right = [-1e6144d, 1e6144d, 1e-6176d, 0d, 0d, -1e6144d, 0d, 1d]
        expected = [1, -1, -1, -1, 1, 1, 0, -1]
    else if name == "gaps":
        left = [1e6144d, -1e6144d, 1e-6176d, -1e-6176d, 1e34d, -1e34d, 1e-33d, -1e-33d]
        right = [
            1e-6176d, -1e-6176d, 1e6144d, -1e6144d, 9999999999999999999999999999999999d,
            -9999999999999999999999999999999999d, 9999999999999999999999999999999999d,
            -9999999999999999999999999999999999d
        ]
        expected = [1, -1, -1, 1, 1, -1, -1, 1]
    else if name == "align":
        left = [
            1.1d, 9.99d, 9999999999999999999999999999999999d,
            9999999999999999999999999999999999d, -1.1d, -9.99d,
            -9999999999999999999999999999999999d, -9999999999999999999999999999999999d
        ]
        right = [1d, 10d, 1e33d, 9e33d, -1d, -10d, -1e33d, -9e33d]
        expected = [1, -1, 1, 1, -1, 1, -1, -1]
    else if name == "large":
        left = [
            9999999999999999999999999999999999d, -9999999999999999999999999999999999d,
            9.999999999999999999999999999999999e6144d,
            -9.999999999999999999999999999999999e6144d, 1e-6176d, -1e-6176d,
            1234567890123456789012345678901234e-30d,
            -1234567890123456789012345678901234e-30d
        ]
        right = [
            9999999999999999999999999999999998d, -9999999999999999999999999999999998d,
            9.999999999999999999999999999999998e6144d,
            -9.999999999999999999999999999999998e6144d, 2e-6176d, -2e-6176d,
            123456789012345678901234567890123e-29d,
            -123456789012345678901234567890123e-29d
        ]
        expected = [1, -1, 1, -1, -1, 1, 1, -1]
    else:
        return 2

    for i in 0..left.length():
        if left[i].compare(right[i]) != expected[i]:
            return 1

    let timer = clock()
    var checksum = 0
    let start = timer.now()
    for i in 0..count:
        checksum += (
            left[i % left.length()].compare(right[i % right.length()])
            * (i % 7 + 1)
        )

    let elapsed = timer.now().difference(start).to_nanoseconds()
    stdout().write("case={name} count={count} ns={elapsed} checksum={checksum}\n").get()
    return 0
