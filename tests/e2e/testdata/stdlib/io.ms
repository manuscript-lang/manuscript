import (
	Bytes from "@std/bytes.ms",
	collect, copy, from_bytes, lines, read_all from "@std/io/streams.ms",
	OpenMode, OpenOptions, open, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",

	closed_reader, memory from "./support/streams.ms",
)

test "stream compositions preserve line endings and EOF":
	found := try collect(lines(memory("one\r\ntwo\nlast")), none)
	try expect_equal(found, ["one", "two", "last"])

	directory := try temporary("manuscript-io-")
	path := "{directory.path()}/copy.bin"
	file := try open(path, OpenMode.Write, OpenOptions(permissions: 420))
	moved := try copy(from_bytes("é🙂".to_bytes()), try file.writer())
	try expect_equal(moved > 0, true)
	try expect_equal((try read_file(path).wait()), "é🙂".to_bytes())

test "streams enforce byte limits and preserve original errors":
	limited: Bytes! := error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))
	try expect_equal(read_all(memory("abc"), 2), limited)

	closed: Bytes! := error(Error("I/O: resource is closed", kind: "EBADF"))
	try expect_equal(read_all(closed_reader(), none), closed)

test "a reader keeps the shared file open after the handle closes":
	directory := try temporary("manuscript-closed-lines-")
	path := "{directory.path()}/lines.txt"
	try write_file(path, "first\nsecond\nlast").wait()

	var handle = try open(path, OpenMode.Read, OpenOptions(permissions: 384))
	var input = lines(try handle.reader())
	try expect_equal((try input.next()), "first")
	try handle.close()
	try expect_equal((try input.next()), "second")
