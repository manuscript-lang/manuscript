import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {ReadStream, WriteStream, IoError, read_all, read_line, copy} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import MemoryStream from "./support/streams.ms"

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream(
        data: "one\r\ntwo\nlast".to_bytes(),
        offset: 0,
        closed: false
    )
    let input = ReadStream(reader)
    read_line(input: input) | try expect_ok | try expect_equal(expected: some("one"))
    read_line(input: input) | try expect_ok | try expect_equal(expected: some("two"))
    read_line(input: input) | try expect_ok | try expect_equal(expected: some("last"))
    ((read_line(input: input) | try expect_ok).is_none()) | try expect_true
    let output = MemoryStream(data: "".to_bytes(), offset: 0, closed: false)
    let source = MemoryStream(data: "é🙂".to_bytes(), offset: 0, closed: false)
    try expect_false(
        (
            (
                copy(
                    input: ReadStream(source),
                    output: WriteStream(output),
                    max_bytes: 6
                ) | try expect_ok
            ) != 6
        )
    )
    output.data | try expect_equal(expected: "é🙂".to_bytes())

test "streams enforce byte limits and preserve original errors":
    let reader = MemoryStream(data: "abc".to_bytes(), offset: 0, closed: false)
    let limited: Result[Bytes, IoError] = error(IoError.LimitExceeded)
    read_all(input: ReadStream(reader), max_bytes: 2) | try expect_equal(
        expected: limited
    )
    reader.closed = true
    let closed: Result[Bytes, IoError] = error(IoError.Closed)
    read_all(input: ReadStream(reader)) | try expect_equal(expected: closed)
