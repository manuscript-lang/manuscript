// conform: tags=testing,tier-io
// conform: phase=test
import (
	ReadStream, Sink, Source, WriteStream from "@std/io/io.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// A stream closes its source or sink once, whether the stream is closed by hand or
// dropped.
type Counted:
	log: String

fn var Counted.next() Int?!:
	return ok(null)

fn var Counted.write(move value: Int) Void!:
	return ok()

fn var Counted.flush() Void!:
	return ok()

fn move Counted.close() Void!:
	void append_file(self.log, "x").wait()

fn closes(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8() or ""
	return ""

test "a read stream closes its source once":
	dir := temporary("stream-close-") | expect_ok?
	log := f"{dir.path()}/r.log"
	void append_file(log, "").wait()

	var by_hand = ReadStream[Int](Counted(log.clone()))
	by_hand.close()?
	expect_equal(closes(log), "x")?

test "a write stream closes its sink once":
	dir := temporary("stream-close-") | expect_ok?
	log := f"{dir.path()}/w.log"
	void append_file(log, "").wait()

	var out = WriteStream[Int](Counted(log.clone()))
	out.close()?
	expect_equal(closes(log), "x")?

type Failing:
	unused: Int

fn var Failing.next() Int?!:
	return ok(null)

fn move Failing.close() Void!:
	return error(Error("close failed", kind: "EIO"))

test "an explicit close returns the source's close error":
	var input = ReadStream[Int](Failing(0))
	result := input.close()
	expect_equal(result.is_error(), true)?
	expect_equal(result.err().message, "close failed")?
