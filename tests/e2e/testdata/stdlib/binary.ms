import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {read_integer, write_integer, read_float, write_float, BinaryError} from "@std/binary.ms"
import Bytes from "@std/bytes.ms"

test "binary integer boundaries and both byte orders":
    for little in [false, true]:
        for number in [-9223372036854775808, -32768, -1, 0, 32767, 9223372036854775807]:
            let data = (
                write_integer(
                    value: number,
                    width: 8,
                    signed: true,
                    little_endian: little
                ) | try expect_ok
            )
            (
                (
                    (
                        read_integer(
                            data: data,
                            offset: 0,
                            width: 8,
                            signed: true,
                            little_endian: little
                        ) | try expect_ok
                    ) != number
                )
            ) | try expect_false

        let data = (
            write_integer(
                value: 258,
                width: 2,
                signed: false,
                little_endian: little
            ) | try expect_ok
        )

        if little:
            data | try expect_equal(expected: Bytes([2, 1]))
        else:
            data | try expect_equal(expected: Bytes([1, 2]))

        (
            (
                (
                    read_float(
                        data: write_float(
                            value: -1.25,
                            little_endian: little
                        ),
                        offset: 0,
                        little_endian: little
                    ) | try expect_ok
                ) != -1.25
            )
        ) | try expect_false

test "binary errors preserve domain and range":
    let range_error: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    (
        (
            write_integer(
                value: 256,
                width: 1,
                signed: false,
                little_endian: false
            ) != range_error
        )
    ) | try expect_false
    (
        (
            write_integer(
                value: -1,
                width: 1,
                signed: false,
                little_endian: false
            ) != range_error
        )
    ) | try expect_false
    let invalid: Result[Int, BinaryError] = error(BinaryError.OutOfRange)
    (
        (
            read_integer(
                data: Bytes([0]),
                offset: -1,
                width: 1,
                signed: true,
                little_endian: false
            ) != invalid
        )
    ) | try expect_false
