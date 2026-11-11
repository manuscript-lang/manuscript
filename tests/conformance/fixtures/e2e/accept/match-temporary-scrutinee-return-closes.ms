// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String

fn var Door.close() Unit!:
	_ := append_file(self.log, "{self.id},").wait()

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn open(id: Int, log: String) Door?:
	return Door(id, log.clone())

fn early(log: String) Int:
	match open(1, log.clone()):
		d:
			if d.id == 1: return 10
			return 20
		none:
			return 0

fn late(log: String) Int:
	n := match open(2, log.clone()):
		d: d.id
		none: 0

	return n

fn hand_on(log: String) Door?:
	match open(3, log.clone()):
		d: return d
		none: return none

test "a payload moved out of the arm is not closed by the match":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	kept := hand_on(log.clone())
	logged(log.clone()) | expect_equal("")?
	if kept.is_some():
		logged(log.clone()) | expect_equal("")?

test "return from an arm closes the temporary scrutinee once":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	early(log.clone()) | expect_equal(10)?
	logged(log.clone()) | expect_equal("1,")?

test "falling out of the match closes it once":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	late(log.clone()) | expect_equal(2)?
	logged(log.clone()) | expect_equal("2,")?
