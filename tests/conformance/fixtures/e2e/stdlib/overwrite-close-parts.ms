// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
	log: String
	id: Int

fn var Tracked.close() Unit!:
	_ := append_file(self.log, "{self.id},").wait()

fn track(log: String, id: Int) Tracked:
	return Tracked(log, id)

fn closed(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

type Pair:
	first: Tracked
	second: Tracked

fn replaces_field(log: String) Int:
	var p = Pair(track(log.clone(), 1), track(log.clone(), 2))
	p.first = track(log, 3)
	return p.first.id

fn replaces_element(log: String) Int:
	var xs = [track(log.clone(), 1), track(log.clone(), 2)]
	xs.set(0, track(log, 3))
	return xs.length()

fn replaces_from_end(log: String) Int:
	var xs = [track(log.clone(), 1), track(log.clone(), 2)]
	xs.set(-1, track(log, 3))
	return xs.length()

fn removes_element(log: String) Int:
	var xs = [track(log.clone(), 1), track(log.clone(), 2), track(log, 3)]
	xs.remove(1)
	return xs.length()

test "overwriting a field closes the old value first":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(replaces_field(log.clone()), 3)?
	expect_equal(closed(log), "1,2,3,")?

test "set closes the element it replaces":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(replaces_element(log.clone()), 2)?
	expect_equal(closed(log), "1,2,3,")?

test "set with a negative index closes the element counted from the end":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(replaces_from_end(log.clone()), 2)?
	expect_equal(closed(log), "2,3,1,")?

test "remove closes the element it drops":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(removes_element(log.clone()), 2)?
	expect_equal(closed(log), "2,3,1,")?

fn replaces_map_value(log: String) Int:
	var m = Map[String, Tracked]()
	m.add("a", track(log.clone(), 1))
	m.add("b", track(log.clone(), 2))
	m.add("a", track(log, 3))
	return m.length()

fn adds_new_map_key(log: String) Int:
	var m = Map[String, Tracked]()
	m.add("a", track(log.clone(), 1))
	m.add("b", track(log, 2))
	return m.length()

fn removes_map_value(log: String) Int:
	var m = Map[String, Tracked]()
	m.add("a", track(log.clone(), 1))
	m.add("b", track(log, 2))
	m.remove("a")
	m.remove("missing")
	return m.length()

fn clears_map(log: String) Int:
	var m = Map[String, Tracked]()
	m.add("a", track(log.clone(), 1))
	m.add("b", track(log, 2))
	m.clear()
	return m.length()

test "add over an existing key closes the old value":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(replaces_map_value(log.clone()), 2)?
	expect_equal(closed(log), "1,2,3,")?

test "add under a new key closes nothing until the scope ends":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(adds_new_map_key(log.clone()), 2)?
	expect_equal(closed(log), "2,1,")?

test "remove closes the value it drops":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(removes_map_value(log.clone()), 1)?
	expect_equal(closed(log), "1,2,")?

test "clear closes every value, last inserted first":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(clears_map(log.clone()), 0)?
	expect_equal(closed(log), "2,1,")?

fn splices_elements(log: String) Int:
	var xs = [
		track(log.clone(), 1),
		track(log.clone(), 2),
		track(log.clone(), 3),
		track(log.clone(), 4),
	]
	xs.splice(1, 2, [track(log, 5)])
	return xs.length()

fn pops_into_ignored(log: String) Int:
	var xs = [track(log.clone(), 1), track(log, 2)]
	_last := xs.pop()
	return xs.length()

test "splice closes the deleted elements, last first":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(splices_elements(log.clone()), 3)?
	expect_equal(closed(log), "3,2,4,5,1,")?

test "a popped value bound to an ignored name closes at scope end":
	temporary := temporary("manuscript-overwrite-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(pops_into_ignored(log.clone()), 1)?
	expect_equal(closed(log), "2,1,")?
