import (
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Item:
	id: Int
	log: String

fn var Item.close() Unit!:
	append_file(self.log, "{self.id},").wait()?

interface Sink:
	fn put(item: Item, n: Int) Int

type Counter:
	base: Int

fn Counter.put(item: Item, n: Int) Int: n + self.base

fn keep(item: Item, n: Int) Int: n + item.id

fn pass(item: Item, n: Int) Item: Item(item.id + n, item.log.clone())

fn failing(log: String) Int:
	panic("operand failed")

fn events(log: String) String!:
	bytes := read_file(log).wait()?
	return ok(bytes.decode_utf8().get(""))

fn borrowed_call(log: String) Unit:
	_n := keep(Item(2, log.clone()), failing(log))

fn consuming_call(log: String) Unit:
	_kept := pass(Item(3, log.clone()), failing(log))

fn interface_call(log: String) Unit:
	sink: Sink := Counter(1)
	_n := sink.put(Item(4, log.clone()), failing(log))

test "a failing later operand closes a borrowed resource argument":
	temp := temporary("call-borrowed-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: borrowed_call(log.clone()))?
	expect_contains(fault, "operand failed")?
	expect_equal(events(log)?, "2,")?

test "a failing later operand closes a consumed resource argument":
	temp := temporary("call-consumed-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: consuming_call(log.clone()))?
	expect_contains(fault, "operand failed")?
	expect_equal(events(log)?, "3,")?

test "a failing later operand closes an interface call argument":
	temp := temporary("call-interface-")?
	log := "{temp.path()}/log"
	fault := expect_fault(fn: interface_call(log.clone()))?
	expect_contains(fault, "operand failed")?
	expect_equal(events(log)?, "4,")?
