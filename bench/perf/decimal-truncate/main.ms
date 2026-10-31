import Decimal from "@std/decimal.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let name = args[0]
    let count = args[1].parse_int().get()
    var values: List[Decimal] = []

    if name == "integer":
        values = [
            0d, 1d, -1d, 123456789d, -123456789d, 1000000000000000000d,
            9223372036854775807d, -9223372036854775808d
        ]
    else if name == "fraction":
        values = [
            1.25d, -1.25d, 123456.789d, -123456.789d, 9223372036854775807.9d,
            -9223372036854775808.9d, 0.9999999999999999999999999999999999d,
            -0.9999999999999999999999999999999999d
        ]
    else if name == "overflow":
        values = [
            9223372036854775808d, -9223372036854775809d, 1e19d, -1e19d,
            9999999999999999999999999999999999d, -9999999999999999999999999999999999d,
            1e6144d, -1e6144d
        ]
    else if name == "underflow":
        values = [
            1e-6176d, -1e-6176d, 1e-39d, -1e-39d,
            9999999999999999999999999999999999e-34d,
            -9999999999999999999999999999999999e-34d, 1e-20d, -1e-20d
        ]
    else if name == "scale":
        values = [
            1e18d, -1e18d, 123e15d, -123e15d, 1234567890123456789012345678901234e-16d,
            -1234567890123456789012345678901234e-16d,
            9999999999999999999999999999999999e-33d,
            -9999999999999999999999999999999999e-33d
        ]
    else:
        return 2

    var expected: List[Int?] = []

    if name == "integer":
        expected = [
            0, 1, -1, 123456789, -123456789, 1000000000000000000, 9223372036854775807,
            -9223372036854775808
        ]
    else if name == "fraction":
        expected = [
            1, -1, 123456, -123456, 9223372036854775807, -9223372036854775808, 0, 0
        ]
    else if name == "overflow":
        expected = [none, none, none, none, none, none, none, none]
    else if name == "underflow":
        expected = [0, 0, 0, 0, 0, 0, 0, 0]
    else if name == "scale":
        expected = [
            1000000000000000000, -1000000000000000000, 123000000000000000,
            -123000000000000000, 123456789012345678, -123456789012345678, 9, -9
        ]

    for i in 0..values.length():
        if values[i].truncate_to_int() != expected[i]:
            return 1

    let timer = clock()
    var checksum = 0
    let start = timer.now()
    for i in 0..count:
        checksum += (
            (
                values[i % values.length()].truncate_to_int().get(97)
                % 1000003
            )
            * (i % 7 + 1)
        )

    let elapsed = timer.now().difference(start).to_nanoseconds()
    stdout().write("case={name} count={count} ns={elapsed} checksum={checksum}\n").get()
    return 0
