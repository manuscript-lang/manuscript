# conform: tags=control-flow,formatter,modules,parser,stdlib-binary,stdlib-bytes,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/binary.ms
from "@std/testing.ms" import expect_equal, expect_false
from "@std/bytes.ms" import read_integer, write_integer, read_float, write_float, BinaryError
from "@std/bytes.ms" import Bytes

test "binary integer boundaries and both byte orders":
    for little in [False, True]:
        for number in [-9223372036854775808, -32768, -1, 0, 32767, 9223372036854775807]:
            let data = try write_integer(number, 8, signed: True, little_endian: little)
            try expect_false(
                (
                    (
                        try read_integer(
                            data, 0, 8, signed: True, little_endian: little
                        )
                    ) != number
                )
            )

        let data = try write_integer(258, 2, signed: False, little_endian: little)

        if little:
            try expect_equal(data, Bytes([2, 1]))
        else:
            try expect_equal(data, Bytes([1, 2]))

        try expect_false(
            (
                (
                    try read_float(
                        write_float(
                            -1.25, little_endian: little
                        ),
                        0,
                        little_endian: little
                    )
                ) != -1.25
            )
        )

test "binary errors preserve domain and range":
    let range_error: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    try expect_equal(
        write_integer(256, 1, signed: False, little_endian: False), range_error
    )
    try expect_equal(
        write_integer(-1, 1, signed: False, little_endian: False), range_error
    )

    let invalid: Result[Int, BinaryError] = error(BinaryError.OutOfRange)
    try expect_equal(
        read_integer(Bytes([0]), -1, 1, signed: True, little_endian: False), invalid
    )
