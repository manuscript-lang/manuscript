import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault, expect_ok from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String
	closed: Bool = false
	fail: Bool = false

impl Closeable for Door:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			try append_file(self.log, "{self.id},").wait()
			if self.fail: return error(Error("close failed"))

fn replace(log: String) Unit:
	var doors = [Door(1, log.clone(), fail: true)]
	doors.set(0, Door(9, log))

test "replacement stays owned while the discarded entry closes":
	tmp := temporary("replacement-close-") | try expect_ok
	log := "{tmp.path()}/log"
	message := try expect_fault(fn: replace(log.clone()))
	try expect_contains(message, "a resource could not be closed")

	events := read_file(log).wait().get().decode_utf8().get("")
	try expect_equal(events, "1,9,")

fn replace_in_map(log: String) Unit:
	var doors: Map[Int, Door] = {}
	doors.add(0, Door(1, log.clone(), fail: true))
	doors.add(0, Door(9, log))

test "map replacement keeps the incoming entry owned while the old one closes":
	tmp := temporary("replacement-close-map-") | try expect_ok
	log := "{tmp.path()}/log"
	message := try expect_fault(fn: replace_in_map(log.clone()))
	try expect_contains(message, "a resource could not be closed")

	events := read_file(log).wait().get().decode_utf8().get("")
	try expect_equal(events, "1,9,")
