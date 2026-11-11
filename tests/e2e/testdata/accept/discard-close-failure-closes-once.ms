import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Item:
	id: Int
	log: String
	fail: Bool

impl Closeable for Item:
	var fn close() Unit!:
		append_file(self.log, "{self.id},").wait()?
		if self.fail: return error(Error("close failed"))

fn events(log: String) String!:
	bytes := read_file(log).wait()?
	return ok(bytes.decode_utf8().get(""))

fn list_remove(log: String) Unit:
	var items = [Item(1, log.clone(), true)]
	items.remove(0)

fn map_add(log: String) Unit:
	var m = Map[String, Item]()
	m.add("a", Item(1, log.clone(), true))
	m.add("a", Item(2, log, false))

fn map_remove(log: String) Unit:
	var m = Map[String, Item]()
	m.add("a", Item(1, log.clone(), true))
	m.remove("a")

fn list_splice(log: String) Unit:
	var items = [Item(1, log.clone(), true), Item(5, log.clone(), false)]
	items.splice(0, 1, [])

test "remove whose close fails closes the entry once":
	temp := temporary("w1-")?
	log := "{temp.path()}/log"
	_f := expect_fault(fn: list_remove(log.clone()))?
	expect_equal(events(log)?, "1,")?

test "map add over an entry whose close fails closes each once":
	temp := temporary("w2-")?
	log := "{temp.path()}/log"
	_f := expect_fault(fn: map_add(log.clone()))?
	expect_equal(events(log)?, "1,2,")?

test "map remove whose close fails closes the entry once":
	temp := temporary("w3-")?
	log := "{temp.path()}/log"
	_f := expect_fault(fn: map_remove(log.clone()))?
	expect_equal(events(log)?, "1,")?

test "splice over an entry whose close fails closes each once":
	temp := temporary("w4-")?
	log := "{temp.path()}/log"
	_f := expect_fault(fn: list_splice(log.clone()))?
	expect_equal(events(log)?, "1,5,")?

fn list_set(log: String) Unit:
	var items = [Item(1, log.clone(), true)]
	items.set(0, Item(2, log, false))

test "set over an entry whose close fails closes each once":
	temp := temporary("w5-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: list_set(log.clone()))?
	expect_contains(fault, "could not be closed")?
	expect_equal(events(log)?, "1,2,")?
