// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_fault, expect_ok from "@std/test/test.ms",
)

// A close that changes its receiver works on the value where it lives: a holder, a
// part, a closure's capture or the cleanup stack sees the closed state afterwards, so a
// second close of the same value (an explicit close followed by the scope end) logs
// nothing.
type Latch:
	log String
	id Int
	open Bool

fn move Latch.close() Void!:
	if self.open:
		self.open = false
		void append_file(self.log, f"{self.id},").wait()

fn latch(move log String, id Int) Latch:
	return Latch(log, id, true)

fn closed(log String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8() or ""
	return ""

type Holder:
	inner Latch
	tag Int

enum Slot:
	Full(inner Latch)
	Empty

fn explicit_then_scope(move log String) Int!:
	var one = latch(log, 1)
	one.close()?
	return ok(1)

fn holder_part(move log String) Int:
	holder := Holder(latch(log, 2), 0)
	return holder.tag

fn optional_part(move log String) Int:
	maybe Latch? := latch(log, 3)
	if maybe != null: return 1

	return 0

fn list_parts(move log String) Int:
	xs := [latch(log.clone(), 4), latch(log, 5)]
	return xs.length()

fn case_part(move log String) Int:
	slot := Full(latch(log, 6))

	n := match slot:
		Full(inner) => inner.id
		Empty => 0

	return n

fn make_closure(move log String) fn() Int:
	held := latch(log, 7)
	return () => held.id

fn closure_capture(move log String) Int:
	f := make_closure(log)
	return f()

fn map_values(move log String) Int:
	var m = Map[String, Latch]()
	m.add("a", latch(log, 8))
	return m.length()

fn fault_through_holder(move log String) Void:
	holder := Holder(latch(log, 9), 0)
	panic("holder fault")
	void holder.tag

fn fault_plain(move log String) Void:
	one := latch(log, 10)
	panic("plain fault")
	void one.id

fn destructured_record(move log String) Int:
	holder := Holder(latch(log, 13), 3)
	{inner: part, tag: n} := holder
	return part.id + n

fn destructured_list(move log String) Int:
	xs := [latch(log.clone(), 14), latch(log, 15)]
	[first, _] := xs
	return first.id

// A resource that hands out other resources: what it returns is the caller's to close
// (#2435).
type Maker:
	made Int

fn move Maker.close() Void!:
	return ok()

fn var Maker.make(move log String, id Int) Latch:
	self.made += 1
	return latch(log, id)

fn var Maker.find(move log String, id Int) Latch?:
	self.made += 1
	return latch(log, id)

fn made_by_resource(move log String) Int:
	var maker = Maker(0)
	var made = maker.make(log, 16)
	return made.id + maker.made

fn found_by_resource(move log String) Int:
	var maker = Maker(0)
	found := maker.find(log, 17)
	if found != null: return found.id

	return 0

fn reassigned(move log String, swap Bool) Int:
	var one = latch(log.clone(), 11)
	if swap:
		one = latch(log, 12)
	return one.id

test "an explicit close followed by the scope end closes once":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(explicit_then_scope(log.clone())?, 1)?
	expect_equal(closed(log), "1,")?

test "a holder's part closes in place at the scope end":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(holder_part(log.clone()), 0)?
	expect_equal(closed(log), "2,")?

test "an optional payload closes in place":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(optional_part(log.clone()), 1)?
	expect_equal(closed(log), "3,")?

test "list elements close in place, last first":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(list_parts(log.clone()), 2)?
	expect_equal(closed(log), "5,4,")?

test "a case field closes in place":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(case_part(log.clone()), 6)?
	expect_equal(closed(log), "6,")?

test "a closure's capture closes when the closure is dropped":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(closure_capture(log.clone()), 7)?
	expect_equal(closed(log), "7,")?

test "a part a record pattern binds closes at the scope end":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(destructured_record(log.clone()), 16)?
	expect_equal(closed(log), "13,")?

test "a list pattern closes the elements it binds and the ones it drops":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(destructured_list(log.clone()), 14)?
	expect_equal(closed(log), "15,14,")?

test "a resource a method on another resource returns closes at the scope end":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(made_by_resource(log.clone()), 17)?
	expect_equal(closed(log), "16,")?

test "a resource payload a method on another resource returns closes with its branch":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(found_by_resource(log.clone()), 17)?
	expect_equal(closed(log), "17,")?

test "map values close in place":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(map_values(log.clone()), 1)?
	expect_equal(closed(log), "8,")?

test "a fault closes a holder's part from the cleanup stack":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	message := expect_fault(() => fault_through_holder(log.clone()))?
	expect_equal(message, "holder fault")?
	expect_equal(closed(log), "9,")?

test "a fault closes a plain binding from the cleanup stack":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	message := expect_fault(() => fault_plain(log.clone()))?
	expect_equal(message, "plain fault")?
	expect_equal(closed(log), "10,")?

test "a reassigned binding closes the replaced value then the final one":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(reassigned(log.clone(), true), 12)?
	expect_equal(closed(log), "11,12,")?

test "a binding kept to the end closes once":
	temporary := temporary("manuscript-close-in-place-") | expect_ok?
	log := f"{temporary.path()}/log"
	expect_equal(reassigned(log.clone(), false), 11)?
	expect_equal(closed(log), "11,")?
