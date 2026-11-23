// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	from_bytes, read_all from "@std/io/streams.ms",
	OpenMode, OpenOptions, open, read_file, temporary, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	expect_golden, expect_golden_bytes from "@std/test/golden.ms",
	check_reader, fail_after, fail_writer_after, one_byte from "@std/test/iotest.ms",
	expect_contains,
	expect_equal,
	expect_error,
	expect_ok,
	expect_true from "@std/test/test.ms",
)

fn source() ReadStream[Bytes]:
	return from_bytes("hello, world".to_bytes(), 5)

test "a plain stream passes the reader check":
	check_reader(source, "hello, world".to_bytes())?

test "a wrong expectation fails the reader check":
	cause := expect_error(check_reader(source, "hello".to_bytes()))?
	expect_contains(cause.message, "check_reader")?

test "one_byte returns single bytes":
	var input = one_byte(source())
	chunk := input.next()?
	expect_equal(chunk.get().length(), 1)?

test "fail_after delivers a prefix and then fails":
	var input = fail_after(
		source(),
		4,
		Error("I/O: service unavailable", kind: "EAGAIN"),
	)
	all := read_all(input, none)
	expect_true(all.is_error())?

test "fail_writer_after writes the prefix that fits and then fails":
	dir := expect_ok(temporary("iotest-"))?
	path := join([dir.path(), "out.bin"])
	file := expect_ok(open(path, OpenMode.Write, OpenOptions(permissions: 420)))?
	var out = fail_writer_after(
		expect_ok(file.writer())?,
		3,
		Error("I/O: service unavailable", kind: "EAGAIN"),
	)
	expect_ok(out.write("ab".to_bytes()))?
	expect_true(out.write("cdef".to_bytes()).is_error())?
	expect_true(out.write("g".to_bytes()).is_error())?
	expect_ok(out.close())?
	expect_equal(expect_ok(read_file(path, none).wait())?, "abc".to_bytes())?

test "golden comparison passes and names the first differing line":
	dir := expect_ok(temporary("golden-"))?
	path := join([dir.path(), "out.txt"])
	expect_ok(write_file(path, "a\nb\nc", true).wait())?
	expect_golden(path, "a\nb\nc")?

	cause := expect_error(expect_golden(path, "a\nx\nc"))?
	expect_contains(cause.message, "line 2")?
	expect_contains(cause.message, "MS_UPDATE_GOLDEN=1")?

	missing := expect_error(expect_golden(join([dir.path(), "none.txt"]), "a"))?
	expect_contains(missing.message, "missing")?

	bytes := expect_error(expect_golden_bytes(path, "a\nb\nd".to_bytes()))?
	expect_contains(bytes.message, "byte 4")?
