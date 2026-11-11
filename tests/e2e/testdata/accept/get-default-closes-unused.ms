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

fn present(log: String) Int:
	held: Door? := Door(1, log.clone())
	door := held.get(Door(2, log.clone()))
	return door.id

fn absent(log: String) Int:
	held: Door? := none
	door := held.get(Door(3, log.clone()))
	return door.id

fn named(log: String) Int:
	held: Door? := Door(4, log.clone())
	spare := Door(5, log.clone())
	door := held.get(spare)
	return door.id + 8

test "an unused temporary default closes at once":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	expect_equal(present(log.clone()), 1)?
	logged(log.clone()) | expect_equal("2,1,")?

test "a used default closes with its binding":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	expect_equal(absent(log.clone()), 3)?
	logged(log.clone()) | expect_equal("3,")?

test "a named default moves into get and closes with the call":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	expect_equal(named(log.clone()), 12)?
	logged(log.clone()) | expect_equal("5,4,")?
