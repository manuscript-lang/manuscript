import {
    read_integer,
    write_integer,
    read_float,
    write_float,
    BinaryError
} from "@std/binary.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "binary integer boundaries and both byte orders":
    for little in [false, true]:
        for number in [
            -9223372036854775808,
            -32768,
            -1,
            0,
            32767,
            9223372036854775807
        ]:
            let data = value(
                write_integer(
                    value: number,
                    width: 8,
                    signed: true,
                    little_endian: little
                )
            )
            if (
                value(
                    read_integer(
                        data: data,
                        offset: 0,
                        width: 8,
                        signed: true,
                        little_endian: little
                    )
                ) != number
            ): return panic("signed roundtrip")

        let data = value(
            write_integer(
                value: 258,
                width: 2,
                signed: false,
                little_endian: little
            )
        )

        if little:
            if data != Bytes([2, 1]): return panic("little endian vector")
        else:
            if data != Bytes([1, 2]): return panic("big endian vector")

        if (
            value(
                read_float(
                    data: write_float(
                        value: -1.25,
                        little_endian: little
                    ),
                    offset: 0,
                    little_endian: little
                )
            ) != -1.25
        ): return panic("float roundtrip")

test "binary errors preserve domain and range":
    let range_error: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    if (
        write_integer(
            value: 256,
            width: 1,
            signed: false,
            little_endian: false
        ) != range_error
    ): return panic("unsigned overflow")
    if (
        write_integer(
            value: -1,
            width: 1,
            signed: false,
            little_endian: false
        ) != range_error
    ): return panic("negative unsigned")

    let invalid: Result[Int, BinaryError] = error(BinaryError.OutOfRange)
    if (
        read_integer(
            data: Bytes([0]),
            offset: -1,
            width: 1,
            signed: true,
            little_endian: false
        ) != invalid
    ): return panic("negative offset")
