// conform: tags=testing,tier-io
// conform: phase=test
import (
	ReadStream, Sink, Source, WriteStream from "@std/io/io.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Counted:
	log: String

fn var Counted.next() Int?!:
	return ok(none)

fn var Counted.write(value: Int) Unit!:
	return ok(unit)

fn var Counted.flush() Unit!:
	return ok(unit)

fn var Counted.close() Unit!:
	_ := append_file(self.log, "x").wait()

fn closes(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

test "read stream closes through the one close":
	dir := temporary("shape-") | expect_ok?
	log := "{dir.path()}/r.log"
	_ := append_file(log, "").wait()
	var by_hand = ReadStream[Int](Counted(log.clone()))
	by_hand.close()?
	expect_equal(closes(log), "x")?

test "write stream closes through the one close":
	dir := temporary("shape-") | expect_ok?
	log := "{dir.path()}/w.log"
	_ := append_file(log, "").wait()
	var out = WriteStream[Int](Counted(log.clone()))
	out.close()?
	expect_equal(closes(log), "x")?

test "a scope closes the value once":
	dir := temporary("shape-") | expect_ok?
	log := "{dir.path()}/s.log"
	_ := append_file(log, "").wait()

	if true:
		c := Counted(log.clone())
		expect_equal(c.log, log)?

	expect_equal(closes(log), "x")?
