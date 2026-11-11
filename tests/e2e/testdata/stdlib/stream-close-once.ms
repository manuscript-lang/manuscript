import (
	ReadStream, Sink, Source, WriteStream from "@std/io/io.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// A stream closes its source or sink once, whether the stream is closed by hand or dropped.
type Counted:
	log: String

impl Source[Int] for Counted:
	var fn next() Int?!:
		return ok(none)

	var fn close() Unit!:
		_ := append_file(self.log, "r").wait()

impl Sink[Int] for Counted:
	var fn write(value: Int) Unit!:
		return ok(unit)

	var fn flush() Unit!:
		return ok(unit)

	var fn close() Unit!:
		_ := append_file(self.log, "w").wait()

fn closes(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

test "a read stream closes its source once":
	dir := temporary("stream-close-") | expect_ok?
	log := "{dir.path()}/r.log"
	_ := append_file(log, "").wait()
	var by_hand = ReadStream[Int](Counted(log.clone()))
	by_hand.close()?
	expect_equal(closes(log), "r")?

test "a write stream closes its sink once":
	dir := temporary("stream-close-") | expect_ok?
	log := "{dir.path()}/w.log"
	_ := append_file(log, "").wait()
	var out = WriteStream[Int](Counted(log.clone()))
	out.close()?
	expect_equal(closes(log), "w")?

type Failing:
	unused: Int

fn var Failing.next() Int?!:
	return ok(none)

fn var Failing.close() Unit!:
	return error(Error("close failed", kind: "EIO"))

test "an explicit close returns the source's close error":
	var input = ReadStream[Int](Failing(0))
	result := input.close()
	expect_equal(result.is_error(), true)?
	expect_equal(result.err().message, "close failed")?
