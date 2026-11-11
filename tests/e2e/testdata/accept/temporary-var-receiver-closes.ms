import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String
	swings: Int

fn var Door.close() Unit!:
	_ := append_file(self.log, "{self.id},").wait()

fn var Door.swing() Int:
	self.swings += 1
	return self.swings

fn Door.peek() Int:
	return self.swings

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn open_door(id: Int, log: String) Door:
	return Door(id, log, 0)

// A temporary that a `var fn` changes in place is still a temporary: it closes when its statement ends.
test "a temporary receiver of a var method closes at the end of its statement":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	first := open_door(1, log.clone()).swing()
	second := open_door(2, log.clone()).peek()
	expect_equal(first + second, 1)?
	expect_equal(logged(log), "1,2,")?
