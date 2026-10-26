# conform: tags=formatter,modules,optional,parser,stdlib-bytes,stdlib-io,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/io.ms
from "@std/test.ms" import expect_equal, expect_false
from "@std/io.ms" import ReadStream, WriteStream, IoError, read_all, read_line, copy
from "@std/bytes.ms" import Bytes
from "./support/streams.ms" import MemoryStream

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream("one\r\ntwo\nlast".to_bytes(), 0, closed: False)
    let input = ReadStream(reader)
    try expect_equal((try read_line(input)), some("one"))
    try expect_equal((try read_line(input)), some("two"))
    try expect_equal((try read_line(input)), some("last"))
    try expect_false(not (try read_line(input)).is_none())

    let output = MemoryStream("".to_bytes(), 0, closed: False)
    let source = MemoryStream("é🙂".to_bytes(), 0, closed: False)
    try expect_equal((try copy(ReadStream(source), WriteStream(output), 6)), 6)
    try expect_equal(output.data, "é🙂".to_bytes())

test "streams enforce byte limits and preserve original errors":
    var reader = MemoryStream("abc".to_bytes(), 0, closed: False)
    let limited: Result[Bytes, IoError] = error(IoError.LimitExceeded)
    try expect_equal(read_all(ReadStream(reader), 2), limited)
    reader.closed = True

    let closed: Result[Bytes, IoError] = error(IoError.Closed)
    try expect_equal(read_all(ReadStream(reader)), closed)
