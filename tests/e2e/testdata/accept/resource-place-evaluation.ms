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
	payload: List[String] = ["owned"]

impl Closeable for Door:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			try append_file(self.log, "{self.id},").wait()
			if self.fail: return error(Error("close failed"))

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn next(var calls: Int) Int:
	selected := calls % 2
	calls += 1
	return selected

fn replacement(log: String, var events: List[Int]) Door:
	events.append(2)
	return Door(9, log)

fn select(var events: List[Int]) Int:
	events.append(1)
	return 0

fn replace(log: String, var calls: Int) Unit:
	var rows = [[Door(1, log.clone())], [Door(2, log.clone())]]
	rows[next(var calls)].set(0, Door(9, log))

test "resource replacement closes and changes the same selected owner":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var calls = 0
	replace(log.clone(), var calls)
	try expect_equal(calls, 1)
	try expect_equal(logged(log), "1,2,9,")

fn ordered(log: String, var events: List[Int]) Unit:
	var rows = [[Door(1, log.clone())]]
	rows[select(var events)].set(0, replacement(log, var events))

test "a resource receiver is selected before its replacement argument":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var events: List[Int] = []
	ordered(log.clone(), var events)
	try expect_equal(events, [1, 2])
	try expect_equal(logged(log), "1,9,")

fn clear_map(log: String, var calls: Int) Unit:
	var maps = [{"a": Door(1, log.clone())}, {"a": Door(2, log)}]
	maps[next(var calls)].clear()

test "resource map clear retains its selection across entry cleanup":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var calls = 0
	clear_map(log.clone(), var calls)
	try expect_equal(calls, 1)
	try expect_equal(logged(log), "1,2,")

fn remove_and_splice(log: String, var calls: Int) Unit:
	var rows = [[Door(1, log.clone()), Door(3, log.clone())], [Door(2, log.clone())]]
	rows[next(var calls)].remove(0)
	rows[next(var calls)].splice(0, 1, [Door(9, log)])

test "resource remove and splice each select the owner once":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var calls = 0
	remove_and_splice(log.clone(), var calls)
	try expect_equal(calls, 2)
	try expect_equal(logged(log), "1,2,9,3,")

fn add_and_remove(log: String, var calls: Int) Unit:
	var maps = [{"a": Door(1, log.clone())}, {"a": Door(2, log.clone())}]
	maps[next(var calls)].add("a", Door(9, log))
	maps[next(var calls)].remove("a")

test "resource map add and remove each select the owner once":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var calls = 0
	add_and_remove(log.clone(), var calls)
	try expect_equal(calls, 2)
	try expect_equal(logged(log), "1,2,9,")

fn failed_argument(var events: List[Int]) Int!:
	events.append(2)
	return error(Error("stop"))

fn propagate(log: String, var events: List[Int]) Unit!:
	var rows = [[Door(1, log)]]
	rows[select(var events)].remove(try failed_argument(var events))

test "a propagated resource argument preserves receiver effects and cleanup":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var events: List[Int] = []
	try expect_equal(propagate(log.clone(), var events).is_error(), true)
	try expect_equal(events, [1, 2])
	try expect_equal(logged(log), "1,")

fn failing_remove(log: String, var calls: Int) Unit:
	var rows = [
		[Door(1, log.clone(), fail: true), Door(2, log.clone())],
		[Door(3, log)],
	]
	rows[next(var calls)].remove(0)

test "a failed entry close preserves its owner and closes the remaining siblings":
	tmp := temporary("resource-place-") | try expect_ok
	log := "{tmp.path()}/log"
	var calls = 0
	message := try expect_fault(fn: failing_remove(log.clone(), var calls))
	try expect_contains(message, "a resource could not be closed")
	try expect_equal(logged(log), "1,3,2,")
