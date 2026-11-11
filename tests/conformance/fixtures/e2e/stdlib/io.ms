// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	collect, copy, from_bytes, lines, read_all from "@std/io/streams.ms",
	OpenMode, OpenOptions, open, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	closed_reader, memory from "./support/streams.ms",
)

test "stream compositions preserve line endings and EOF":
	found := collect(lines(memory("one\r\ntwo\nlast")), none)?
	expect_equal(found, ["one", "two", "last"])?

	directory := temporary("manuscript-io-")?
	path := "{directory.path()}/copy.bin"
	file := open(path, OpenMode.Write, OpenOptions(permissions: 420))?
	moved := copy(from_bytes("é🙂".to_bytes()), file.writer()?)?
	expect_equal(moved > 0, true)?
	expect_equal((read_file(path).wait()?), "é🙂".to_bytes())?

test "streams enforce byte limits and preserve original errors":
	limited: Bytes! := error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(read_all(memory("abc"), 2), limited)?

	closed: Bytes! := error(Error("I/O: resource is closed", kind: "EBADF"))
	expect_equal(read_all(closed_reader(), none), closed)?

test "a reader keeps the shared file open after the handle closes":
	directory := temporary("manuscript-closed-lines-")?
	path := "{directory.path()}/lines.txt"
	write_file(path, "first\nsecond\nlast").wait()?

	var handle = open(path, OpenMode.Read, OpenOptions(permissions: 384))?
	var input = lines(handle.reader()?)
	expect_equal((input.next()?), "first")?
	handle.close()?
	expect_equal((input.next()?), "second")?
