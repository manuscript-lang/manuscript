import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String

impl Closeable for Door:
	var fn close() Unit!:
		_ := append_file(self.log, "{self.id},").wait()

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn first_even(log: String) Int:
	doors := [Door(1, log.clone()), Door(2, log.clone()), Door(3, log.clone())]
	for d in doors:
		if d.id % 2 == 0: return d.id
	return -1

fn until_two(log: String) Int:
	doors := [Door(1, log.clone()), Door(2, log.clone()), Door(3, log.clone())]
	var n = 0

	for d in doors:
		n += d.id
		if d.id == 2: break

	return n

test "return out of an owned loop closes every element once":
	tmp := temporary("ms-log-") | try expect_ok
	log := "{tmp.path()}/log"
	first_even(log.clone()) | try expect_equal(2)
	logged(log.clone()) | try expect_equal("1,2,3,")

test "break closes the elements it never reached":
	tmp := temporary("ms-log-") | try expect_ok
	log := "{tmp.path()}/log"
	until_two(log.clone()) | try expect_equal(3)
	logged(log.clone()) | try expect_equal("1,2,3,")
