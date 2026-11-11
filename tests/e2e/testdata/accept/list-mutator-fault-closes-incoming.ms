import (
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Item:
	id: Int
	log: String

impl Closeable for Item:
	var fn close() Unit!:
		append_file(self.log, "{self.id},").wait()?

fn set_out(log: String) Unit:
	var items = [Item(1, log.clone())]
	items.set(10, Item(2, log))

fn insert_out(log: String) Unit:
	var items = [Item(1, log.clone())]
	items.insert(10, Item(2, log))

fn replace_out(log: String) Unit:
	var items = [Item(1, log.clone())]
	_old := items.replace(10, Item(2, log))

fn events(log: String) String!:
	bytes := read_file(log).wait()?
	return ok(bytes.decode_utf8().get(""))

test "set bounds fault closes the incoming resource first":
	temp := temporary("list-set-cleanup-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: set_out(log.clone()))?
	expect_contains(fault, "index")?
	expect_equal(events(log)?, "2,1,")?

test "insert bounds fault closes the incoming resource first":
	temp := temporary("list-insert-cleanup-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: insert_out(log.clone()))?
	expect_contains(fault, "index")?
	expect_equal(events(log)?, "2,1,")?

test "replace bounds fault closes the incoming resource first":
	temp := temporary("list-replace-cleanup-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: replace_out(log.clone()))?
	expect_contains(fault, "index")?
	expect_equal(events(log)?, "2,1,")?

fn failing_index(log: String) Int:
	panic("index operand failed")

fn set_operand_fault(log: String) Unit:
	var items = [Item(1, log.clone())]
	items.set(value: Item(2, log.clone()), index: failing_index(log))

test "a failing later operand closes the incoming resource":
	temp := temporary("list-operand-cleanup-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: set_operand_fault(log.clone()))?
	expect_contains(fault, "index operand failed")?
	expect_equal(events(log)?, "2,1,")?

test "set with a negative named index closes the old entry then stores":
	temp := temporary("list-negative-named-")?
	log := "{temp.path()}/log"
	var items = [Item(1, log.clone()), Item(2, log.clone())]
	items.set(value: Item(3, log.clone()), index: -1)
	expect_equal(events(log)?, "2,")?
	expect_equal(items.length(), 2)?

fn remove_out(log: String) Unit:
	var items = [Item(1, log)]
	items.remove(10)

test "remove bounds fault still closes the list's existing resource":
	temp := temporary("list-remove-cleanup-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: remove_out(log.clone()))?
	expect_contains(fault, "index")?
	expect_equal(events(log)?, "1,")?
