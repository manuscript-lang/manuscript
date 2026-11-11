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

type Slot:
	door: Door

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn put(var slot: Slot, door: Door) Unit:
	slot.door = door

fn stash(var doors: List[Door], door: Door) Unit:
	doors.append(door)

test "a temporary passed to a var-parameter function that keeps it closes once, later":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	var slot = Slot(Door(1, log.clone()))
	put(var slot, Door(2, log.clone()))
	logged(log.clone()) | expect_equal("1,")?
	expect_equal(slot.door.id, 2)?

test "a list a var-parameter function appends a temporary to closes it with the list":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	var doors = List[Door]()
	stash(var doors, Door(3, log.clone()))
	logged(log.clone()) | expect_equal("")?
	expect_equal(doors.length(), 1)?
