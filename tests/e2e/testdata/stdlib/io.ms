from "@std/testing.ms" import expect_equal, expect_false
from "@std/io.ms" import ReadStream, WriteStream, IoError, read_all, read_line, copy
from "@std/bytes.ms" import Bytes
from "@std/fs.ms" import filesystem
from "./support/streams.ms" import MemoryStream

test "stream compositions invoke source implementations and preserve EOF":
    let reader = MemoryStream("one\r\ntwo\nlast".to_bytes(), 0, closed: False)
    let input: ReadStream = reader
    try expect_equal((try read_line(input)), some("one"))
    try expect_equal((try read_line(input)), some("two"))
    try expect_equal((try read_line(input)), some("last"))
    try expect_false(not (try read_line(input)).is_none())

    let fs = filesystem()

    with let directory = try fs.temporary("manuscript-io-"):
        let path = f"{directory.path()}/copy.bin"
        let file = try fs.open(path: path, flags: "w", mode: 420)
        let source = MemoryStream("é🙂".to_bytes(), 0, closed: False)
        try expect_equal((try copy(source, file.writer(), 6)), 6)
        try expect_equal((try fs.read_file(path)), "é🙂".to_bytes())

test "streams enforce byte limits and preserve original errors":
    var reader = MemoryStream("abc".to_bytes(), 0, closed: False)
    let limited: Result[Bytes, IoError] = error(IoError.LimitExceeded)
    try expect_equal(read_all(reader.clone(), 2), limited)
    reader.closed = True

    let closed: Result[Bytes, IoError] = error(IoError.Closed)
    try expect_equal(read_all(reader), closed)

test "native line reads reject buffered lines after the shared file is closed":
    let fs = filesystem()
    with let directory = try fs.temporary("manuscript-closed-lines-"):
        let path = f"{directory.path()}/lines.txt"
        try fs.write_file(path, "first\nsecond\nlast")
        let handle = try fs.open(path, "r", 384)
        let input = handle.reader()
        try expect_equal((try read_line(input)), some("first"))
        handle.close()
        let closed: Result[Optional[String], IoError] = error(IoError.Closed)
        try expect_equal(read_line(input), closed)
