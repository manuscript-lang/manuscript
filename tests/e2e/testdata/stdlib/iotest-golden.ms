import IoError, ReadStream, read_all from "@std/io/io.ms"
import from_bytes from "@std/io/streams.ms"
import join, open, read_file, temporary, write_file from "@std/os/fs.ms"
import (
    expect_equal,
    expect_error,
    expect_contains,
    expect_ok,
    expect_true
) from "@std/test/test.ms"
import check_reader, fail_after, fail_writer_after, one_byte from "@std/test/iotest.ms"
import expect_golden, expect_golden_bytes from "@std/test/golden.ms"

fn source() ReadStream:
    return from_bytes("hello, world".to_bytes(), 5)

test "a plain stream passes the reader check":
    try check_reader(source, "hello, world".to_bytes())

test "a wrong expectation fails the reader check":
    let cause = try expect_error(check_reader(source, "hello".to_bytes()))
    try expect_contains(cause.message(), "check_reader")

test "one_byte returns single bytes":
    var input = one_byte(source())
    let chunk = try input.read(100)
    try expect_equal(chunk.get().length(), 1)

test "fail_after delivers a prefix and then fails":
    var input = fail_after(source(), 4, IoError.Unavailable)
    let all = read_all(input, none)
    try expect_true(all.is_error())

test "fail_writer_after writes the prefix that fits and then fails":
    let dir = try expect_ok(temporary("iotest-"))
    let path = join([dir.path(), "out.bin"])
    let file = try expect_ok(open(path, "w", 420))
    var out = fail_writer_after(file.writer(), 3, IoError.Unavailable)
    try expect_ok(out.write("ab"))
    try expect_true(out.write("cdef").is_error())
    try expect_true(out.write("g").is_error())
    out.close()
    try expect_equal(try expect_ok(read_file(path, none)), "abc".to_bytes())

test "golden comparison passes and names the first differing line":
    let dir = try expect_ok(temporary("golden-"))
    let path = join([dir.path(), "out.txt"])
    try expect_ok(write_file(path, "a\nb\nc", true))
    try expect_golden(path, "a\nb\nc")

    let cause = try expect_error(expect_golden(path, "a\nx\nc"))
    try expect_contains(cause.message(), "line 2")
    try expect_contains(cause.message(), "MS_UPDATE_GOLDEN=1")

    let missing = try expect_error(expect_golden(join([dir.path(), "none.txt"]), "a"))
    try expect_contains(missing.message(), "missing")

    let bytes = try expect_error(expect_golden_bytes(path, "a\nb\nd".to_bytes()))
    try expect_contains(bytes.message(), "byte 4")
