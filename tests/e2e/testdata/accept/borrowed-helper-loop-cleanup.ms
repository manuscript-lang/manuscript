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
		try append_file(self.log, "{self.id},").wait()

fn first[T](rows: List[List[T]]) List[T]:
	return rows.get(0)

fn logged(path: String) String:
	if bytes := read_file(path).wait(): return bytes.decode_utf8().get("")
	return ""

fn break_borrowed(log: String) Unit!:
	rows := [[Door(1, log.clone()), Door(2, log.clone())]]

	for door in first(rows):
		door.id | try expect_equal(1)
		break

	logged(log.clone()) | try expect_equal("")
	rows.get(0).get(1).id | try expect_equal(2)

fn return_borrowed(rows: List[List[Door]]) Int:
	for door in first(rows):
		return door.id
	return -1

fn use_after_return(log: String) Unit!:
	rows := [[Door(1, log.clone()), Door(2, log.clone())]]
	return_borrowed(rows) | try expect_equal(1)
	logged(log.clone()) | try expect_equal("")
	rows.get(0).get(1).id | try expect_equal(2)

test "break from a borrowed helper loop leaves resources with their owner":
	tmp := temporary("ms-borrow-loop-") | try expect_ok
	log := "{tmp.path()}/log"
	try break_borrowed(log.clone())
	logged(log.clone()) | try expect_equal("2,1,")

test "return from a borrowed helper loop leaves resources with their owner":
	tmp := temporary("ms-borrow-loop-") | try expect_ok
	log := "{tmp.path()}/log"
	try use_after_return(log.clone())
	logged(log.clone()) | try expect_equal("2,1,")

test "a helper called with a temporary owner keeps its result alive":
	var total = 0
	for number in first([[1, 2], [3, 4]]):
		total += number
	total | try expect_equal(3)

fn fail() Unit!:
	return error(Error("stop"))

fn try_borrowed(rows: List[List[Door]]) Unit!:
	for door in first(rows):
		door.id | try expect_equal(1)
		try fail()

fn use_after_try(log: String) Unit!:
	rows := [[Door(1, log.clone()), Door(2, log.clone())]]
	try_borrowed(rows).is_error() | try expect_equal(true)
	logged(log.clone()) | try expect_equal("")
	rows.get(0).get(1).id | try expect_equal(2)

test "try out of a borrowed helper loop leaves resources with their owner":
	tmp := temporary("ms-borrow-loop-") | try expect_ok
	log := "{tmp.path()}/log"
	try use_after_try(log.clone())
	logged(log.clone()) | try expect_equal("2,1,")
