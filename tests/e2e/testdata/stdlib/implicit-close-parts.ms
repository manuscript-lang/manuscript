import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
	log: String
	id: Int

impl Closeable for Tracked:
	var fn close() Unit!:
		_ := append_file(self.log, "{self.id},").wait()

fn track(log: String, id: Int) Tracked:
	return Tracked(log, id)

fn closed(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

type Pair:
	first: Tracked
	second: Tracked

type Nested:
	pair: Pair
	all: List[Tracked]

enum Slot:
	Empty
	Full(item: Tracked)
	Both(left: Tracked, right: Tracked)

// Closes itself, then the field it owns.
type Wrapper:
	log: String
	inner: Tracked

impl Closeable for Wrapper:
	var fn close() Unit!:
		_ := append_file(self.log, "wrapper,").wait()

fn holds_fields(log: String) Int:
	p := Pair(track(log.clone(), 1), track(log, 2))
	return p.first.id

fn holds_list(log: String) Int:
	xs := [track(log.clone(), 1), track(log.clone(), 2), track(log, 3)]
	return xs.length()

fn holds_map(log: String) Int:
	var m = Map[String, Tracked]()
	m.add("a", track(log.clone(), 1))
	m.add("b", track(log, 2))
	return m.length()

fn holds_nested(log: String) Int:
	n := Nested(
		Pair(track(log.clone(), 1), track(log.clone(), 2)),
		[track(log.clone(), 3), track(log, 4)],
	)
	return n.all.length()

fn holds_optional(log: String, present: Bool) Int:
	var _held: Tracked? = none
	if present:
		_held = track(log, 1)
	return 0

fn holds_alternative(log: String) Int:
	_both := Slot.Both(track(log.clone(), 1), track(log, 2))
	_empty := Slot.Empty
	return 0

fn holds_wrapper(log: String) Int:
	w := Wrapper(log.clone(), track(log, 1))
	return w.inner.id

fn returns_early(log: String, early: Bool) Int:
	p := Pair(track(log.clone(), 1), track(log, 2))
	if early: return 1

	return p.first.id

fn moves_on(log: String) Pair:
	p := Pair(track(log.clone(), 1), track(log, 2))
	return p

test "a record closes its fields, last declared first":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_fields(log.clone()), 1)?
	expect_equal(closed(log), "2,1,")?

test "a list closes its elements, last first":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_list(log.clone()), 3)?
	expect_equal(closed(log), "3,2,1,")?

test "a map closes its values, last inserted first":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_map(log.clone()), 2)?
	expect_equal(closed(log), "2,1,")?

test "nested records and lists close depth first, last first":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_nested(log.clone()), 2)?
	expect_equal(closed(log), "4,3,2,1,")?

test "an optional closes the resource it holds":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_optional(log.clone(), true), 0)?
	expect_equal(closed(log.clone()), "1,")?

test "an empty optional closes nothing":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_optional(log.clone(), false), 0)?
	expect_equal(closed(log), "")?

test "an alternative closes the fields of the case it holds":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_alternative(log.clone()), 0)?
	expect_equal(closed(log), "2,1,")?

test "a type's own close runs before the resources it holds":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(holds_wrapper(log.clone()), 1)?
	expect_equal(closed(log), "wrapper,1,")?

test "an early return closes the parts":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	expect_equal(returns_early(log.clone(), true), 1)?
	expect_equal(closed(log), "2,1,")?

test "a record handed to the caller is not closed by the callee":
	temporary := temporary("manuscript-parts-") | expect_ok?
	log := "{temporary.path()}/log"
	p := moves_on(log.clone())
	expect_equal(closed(log), "")?
	expect_equal(p.first.id, 1)?
