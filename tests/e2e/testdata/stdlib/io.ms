import expect_equal, expect_false from "@std/test.ms"
import ReadStream, WriteStream, IoError, read_all, read_line, copy from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import filesystem from "@std/fs.ms"
import MemoryStream from "./support/streams.ms"

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream("one\r\ntwo\nlast".to_bytes(), 0, closed: false)
    let input: ReadStream = reader
    try expect_equal((try read_line(input)), "one")
    try expect_equal((try read_line(input)), "two")
    try expect_equal((try read_line(input)), "last")
    try expect_false(not (try read_line(input)).is_none())

    let fs = filesystem()
    let directory = try fs.temporary("manuscript-io-")
    let path = "{directory.path()}/copy.bin"
    let file = try fs.open(path: path, flags: "w", mode: 420)
    let source = MemoryStream("é🙂".to_bytes(), 0, closed: false)
    try expect_equal((try copy(source, file.writer(), 6)), 6)
    try expect_equal((try fs.read_file(path)), "é🙂".to_bytes())

test "streams enforce byte limits and preserve original errors":
    var reader = MemoryStream("abc".to_bytes(), 0, closed: false)
    let limited: Result[Bytes, IoError] = error(IoError.LimitExceeded)
    try expect_equal(read_all(reader.clone(), 2), limited)
    reader.closed = true

    let closed: Result[Bytes, IoError] = error(IoError.Closed)
    try expect_equal(read_all(reader), closed)

test "native line reads reject buffered lines after the shared file is closed":
    let fs = filesystem()
    let directory = try fs.temporary("manuscript-closed-lines-")
    let path = "{directory.path()}/lines.txt"
    try fs.write_file(path, "first\nsecond\nlast")

    var handle = try fs.open(path, "r", 384)
    let input = handle.reader()
    try expect_equal((try read_line(input)), "first")
    try handle.close()

    let closed: Result[String?, IoError] = error(IoError.Closed)
    try expect_equal(read_line(input), closed)
