// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault, expect_ok from "@std/test/test.ms",
)

type Door {
	id Int
	log String
	closed Bool = false
	fail Bool = false
	payload List[String] = ["owned"]
}

fn move Door.close() Void! {
	if not self.closed {
		self.closed = true
		append_file(self.log, f"{self.id},").wait()?
		if self.fail { return error(Error("close failed")) }
	}
}

fn logged(path String) String {
	read := read_file(path).wait()
	if bytes := read { return bytes.decode_utf8() or "" }

	return ""
}

fn next(var calls Int) Int {
	selected := calls % 2
	calls += 1
	return selected
}

fn replacement(move log String, var events List[Int]) Door {
	events.append(2)
	return Door(9, log)
}

fn select(var events List[Int]) Int {
	events.append(1)
	return 0
}

fn replace(move log String, var calls Int) Void {
	var rows = [[Door(1, log.clone())], [Door(2, log.clone())]]
	rows[next(calls)].set(0, Door(9, log))
}

test "resource replacement closes and changes the same selected owner" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var calls = 0
	replace(log.clone(), calls)
	expect_equal(calls, 1)?
	expect_equal(logged(log), "1,2,9,")?
}

fn ordered(move log String, var events List[Int]) Void {
	var rows = [[Door(1, log.clone())]]
	rows[select(events)].set(0, replacement(log, events))
}

test "a resource receiver is selected before its replacement argument" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var events List[Int] = []
	ordered(log.clone(), events)
	expect_equal(events, [1, 2])?
	expect_equal(logged(log), "1,9,")?
}

fn clear_map(move log String, var calls Int) Void {
	var maps = [{"a": Door(1, log.clone())}, {"a": Door(2, log)}]
	maps[next(calls)].clear()
}

test "resource map clear retains its selection across entry cleanup" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var calls = 0
	clear_map(log.clone(), calls)
	expect_equal(calls, 1)?
	expect_equal(logged(log), "1,2,")?
}

fn remove_and_splice(move log String, var calls Int) Void {
	var rows = [[Door(1, log.clone()), Door(3, log.clone())], [Door(2, log.clone())]]
	rows[next(calls)].remove(0)
	rows[next(calls)].splice(0, 1, [Door(9, log)])
}

test "resource remove and splice each select the owner once" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var calls = 0
	remove_and_splice(log.clone(), calls)
	expect_equal(calls, 2)?
	expect_equal(logged(log), "1,2,9,3,")?
}

fn add_and_remove(move log String, var calls Int) Void {
	var maps = [{"a": Door(1, log.clone())}, {"a": Door(2, log.clone())}]
	maps[next(calls)].add("a", Door(9, log))
	maps[next(calls)].remove("a")
}

test "resource map add and remove each select the owner once" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var calls = 0
	add_and_remove(log.clone(), calls)
	expect_equal(calls, 2)?
	expect_equal(logged(log), "1,2,9,")?
}

fn failed_argument(var events List[Int]) Int! {
	events.append(2)
	return error(Error("stop"))
}

fn propagate(move log String, var events List[Int]) Void! {
	var rows = [[Door(1, log)]]
	rows[select(events)].remove(failed_argument(events)?)
}

test "a propagated resource argument preserves receiver effects and cleanup" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var events List[Int] = []
	expect_equal(propagate(log.clone(), events).is_error(), true)?
	expect_equal(events, [1, 2])?
	expect_equal(logged(log), "1,")?
}

fn failing_remove(move log String, var calls Int) Void {
	var rows = [
		[Door(1, log.clone(), fail: true), Door(2, log.clone())],
		[Door(3, log)],
	]
	rows[next(calls)].remove(0)
}

test "a failed entry close preserves its owner and closes the remaining siblings" {
	tmp := temporary("resource-place-") | expect_ok?
	log := f"{tmp.path()}/log"
	var calls = 0
	message := expect_fault(() => failing_remove(log.clone(), calls))?
	expect_contains(message, "a resource could not be closed")?
	expect_equal(logged(log), "1,3,2,")?
}
// expect-exit: 0
// expect-tests: passed=7 failed=0
