// conform: tags=alternatives,closures,control-flow,faults,formatter,generics,interfaces,lists,match,modules,optional,parser,records,stdlib-errors,stdlib-queues,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/optional-arguments.ms
import (
	Queue from "@std/collections/queue.ms",
	panic from "@std/core.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

fn number(value Int?) Int => value or (-1)

fn present[T](value T?) T? => value

fn nested(
	value Int??
) Bool => (value or panic("called Optional.get() on null")).is_none()

fn list_size(
	value List[Int]?
) Int => (value or panic("called Optional.get() on null")).length()

fn flag(value Bool?) Bool => value or panic("called Optional.get() on null")

fn success(value Int!Error?) Int {
	return (value or panic("called Optional.get() on null")).get_or(-1)
}

fn context[T](value T?, fallback T) T {
	inner := value
	if inner != null { return inner }

	return fallback
}

type Notice {
	failure Error?
}

type Box[T] {
	value T?
}

type DefaultBox {
	value Int?
}

enum Choice[T] {
	chosen(value T?)
}

interface Read {
	fn read(value Int?) Int
}

type Reader {
	offset Int
}

fn Reader.read(value Int?) Int => (value or 0) + self.offset

type Counter {
	calls Int
}

fn next(var counter Counter) Int {
	counter.calls += 1
	return counter.calls
}

fn ordered(first Int?, second Int?) Int {
	return (
		(first or panic("called Optional.get() on null")) * 10
		+ (second or panic("called Optional.get() on null"))
	)
}

fn invoke(
	value (fn(Int) Int)?
) Int => (value or panic("called Optional.get() on null"))(4)

fn increment(value Int) Int => value + 1

fn calls_of(
	value Counter?
) Int => (value or panic("called Optional.get() on null")).calls

test "plain values and explicit optionals share the call contract" {
	expect_equal(number(4), 4)?
	expect_equal(number(value: 0), 0)?

	supplied Int? := 4
	expect_equal(number(supplied), 4)?
	expect_equal(number(), -1)?
	expect_equal(number(), -1)?

	stored fn(Int?) Int := number
	expect_equal(stored(5), 5)?
	expect_equal(present(6) or panic("called Optional.get() on null"), 6)?
	expect_equal(present[Int](7) or panic("called Optional.get() on null"), 7)?

	generic_supplied Int? := 8
	expect_equal(present(generic_supplied) or panic("called Optional.get() on null"), 8)?

	missing Int? := null
	expect_false(not (nested(missing)))?

	outer Int?? := missing
	expect_false(not (nested(outer)))?
	expect_equal(list_size([]), 0)?
	expect_equal(list_size([1, 2]), 2)?
	expect_equal(context(value: null, fallback: 9), 9)?
	expect_equal(context(value: [], fallback: [1]).length(), 0)?
	expect_equal(success(ok(10)), 10)?
	expect_false(flag(false))?
	expect_false(flag(true and false))?
	expect_equal(invoke(increment), 5)?
	expect_equal(invoke(value => value + 2), 6)?
}

test "constructor fields and methods use optional arguments" {
	defaulted := DefaultBox()
	expect_false(not (defaulted.value == null))?

	supplied := DefaultBox(3)
	expect_equal(supplied.value or panic("called Optional.get() on null"), 3)?

	box := Box(4)
	expect_equal(box.value or panic("called Optional.get() on null"), 4)?

	choice := Choice.chosen(5)

	match choice {
		chosen(value) => {
			expect_equal(value or panic("called Optional.get() on null"), 5)?
		}
	}

	reader := Reader(2)
	expect_equal(reader.read(3), 5)?

	read := reader.read
	expect_equal(read(4), 6)?

	view Read := reader
	expect_equal(view.read(5), 7)?

	counter := Counter(9)
	expect_equal(calls_of(counter.clone()), 9)?
	expect_equal(counter.calls, 9)?

	notice := Notice(Error("detail"))
	expect_equal(
		(notice.failure or panic("called Optional.get() on null")).message,
		"detail",
	)?
}

test "wrapping evaluates arguments once in written order" {
	var counter = Counter(0)
	expect_equal(ordered(second: next(counter), first: next(counter)), 21)?
	expect_equal(counter.calls, 2)?
}

test "queue capacity accepts a plain value or omission" {
	var bounded = Queue[Int](4)
	for value in [1, 2, 3, 4] {
		expect_false(not (bounded.enqueue(value)))?
	}
	expect_false(bounded.enqueue(5))?
	expect_equal(bounded.dequeue() or panic("called Optional.get() on null"), 1)?

	var unbounded = Queue[Int]()
	var absent = Queue[Int]()
	capacity Int? := 4
	var explicit = Queue[Int](capacity)

	for value in [1, 2, 3, 4, 5] {
		expect_false(not (unbounded.enqueue(value)))?
		expect_false(not (absent.enqueue(value)))?
	}

	expect_false(not (explicit.enqueue(1)))?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tQueue from "@std/collections/queue.ms",
// expect-formatted: \tpanic from "@std/core.ms",
// expect-formatted: \texpect_equal, expect_false from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: fn number(value Int?) Int => value or (-1)
// expect-formatted:
// expect-formatted: fn present[T](value T?) T? => value
// expect-formatted:
// expect-formatted: fn nested(
// expect-formatted: \tvalue Int??
// expect-formatted: ) Bool => (value or panic("called Optional.get() on null")).is_none()
// expect-formatted:
// expect-formatted: fn list_size(
// expect-formatted: \tvalue List[Int]?
// expect-formatted: ) Int => (value or panic("called Optional.get() on null")).length()
// expect-formatted:
// expect-formatted: fn flag(value Bool?) Bool => value or panic("called Optional.get() on null")
// expect-formatted:
// expect-formatted: fn success(value Int!?) Int {
// expect-formatted: \treturn (value or panic("called Optional.get() on null")).get_or(-1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn context[T](value T?, fallback T) T {
// expect-formatted: \tinner := value
// expect-formatted: \tif inner != null { return inner }
// expect-formatted:
// expect-formatted: \treturn fallback
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Notice {
// expect-formatted: \tfailure Error?
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T?
// expect-formatted: }
// expect-formatted:
// expect-formatted: type DefaultBox {
// expect-formatted: \tvalue Int?
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Choice[T] {
// expect-formatted: \tchosen(value T?)
// expect-formatted: }
// expect-formatted:
// expect-formatted: interface Read {
// expect-formatted: \tfn read(value Int?) Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Reader {
// expect-formatted: \toffset Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn Reader.read(value Int?) Int => (value or 0) + self.offset
// expect-formatted:
// expect-formatted: type Counter {
// expect-formatted: \tcalls Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn next(var counter Counter) Int {
// expect-formatted: \tcounter.calls += 1
// expect-formatted: \treturn counter.calls
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn ordered(first, second Int?) Int {
// expect-formatted: \treturn (
// expect-formatted: \t\t(first or panic("called Optional.get() on null")) * 10
// expect-formatted: \t\t+ (second or panic("called Optional.get() on null"))
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn invoke(
// expect-formatted: \tvalue (fn(Int) Int)?
// expect-formatted: ) Int => (value or panic("called Optional.get() on null"))(4)
// expect-formatted:
// expect-formatted: fn increment(value Int) Int => value + 1
// expect-formatted:
// expect-formatted: fn calls_of(
// expect-formatted: \tvalue Counter?
// expect-formatted: ) Int => (value or panic("called Optional.get() on null")).calls
// expect-formatted:
// expect-formatted: test "plain values and explicit optionals share the call contract" {
// expect-formatted: \texpect_equal(number(4), 4)?
// expect-formatted: \texpect_equal(number(value: 0), 0)?
// expect-formatted:
// expect-formatted: \tsupplied Int? := 4
// expect-formatted: \texpect_equal(number(supplied), 4)?
// expect-formatted: \texpect_equal(number(), -1)?
// expect-formatted: \texpect_equal(number(), -1)?
// expect-formatted:
// expect-formatted: \tstored fn(Int?) Int := number
// expect-formatted: \texpect_equal(stored(5), 5)?
// expect-formatted: \texpect_equal(present(6) or panic("called Optional.get() on null"), 6)?
// expect-formatted: \texpect_equal(present[Int](7) or panic("called Optional.get() on null"), 7)?
// expect-formatted:
// expect-formatted: \tgeneric_supplied Int? := 8
// expect-formatted: \texpect_equal(present(generic_supplied) or panic("called Optional.get() on null"), 8)?
// expect-formatted:
// expect-formatted: \tmissing Int? := null
// expect-formatted: \texpect_false(not (nested(missing)))?
// expect-formatted:
// expect-formatted: \touter Int?? := missing
// expect-formatted: \texpect_false(not (nested(outer)))?
// expect-formatted: \texpect_equal(list_size([]), 0)?
// expect-formatted: \texpect_equal(list_size([1, 2]), 2)?
// expect-formatted: \texpect_equal(context(value: null, fallback: 9), 9)?
// expect-formatted: \texpect_equal(context(value: [], fallback: [1]).length(), 0)?
// expect-formatted: \texpect_equal(success(ok(10)), 10)?
// expect-formatted: \texpect_false(flag(false))?
// expect-formatted: \texpect_false(flag(true and false))?
// expect-formatted: \texpect_equal(invoke(increment), 5)?
// expect-formatted: \texpect_equal(invoke(value => value + 2), 6)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "constructor fields and methods use optional arguments" {
// expect-formatted: \tdefaulted := DefaultBox()
// expect-formatted: \texpect_false(not (defaulted.value == null))?
// expect-formatted:
// expect-formatted: \tsupplied := DefaultBox(3)
// expect-formatted: \texpect_equal(supplied.value or panic("called Optional.get() on null"), 3)?
// expect-formatted:
// expect-formatted: \tbox := Box(4)
// expect-formatted: \texpect_equal(box.value or panic("called Optional.get() on null"), 4)?
// expect-formatted:
// expect-formatted: \tchoice := Choice.chosen(5)
// expect-formatted:
// expect-formatted: \tmatch choice {
// expect-formatted: \t\tchosen(value) => {
// expect-formatted: \t\t\texpect_equal(value or panic("called Optional.get() on null"), 5)?
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treader := Reader(2)
// expect-formatted: \texpect_equal(reader.read(3), 5)?
// expect-formatted:
// expect-formatted: \tread := reader.read
// expect-formatted: \texpect_equal(read(4), 6)?
// expect-formatted:
// expect-formatted: \tview Read := reader
// expect-formatted: \texpect_equal(view.read(5), 7)?
// expect-formatted:
// expect-formatted: \tcounter := Counter(9)
// expect-formatted: \texpect_equal(calls_of(counter.clone()), 9)?
// expect-formatted: \texpect_equal(counter.calls, 9)?
// expect-formatted:
// expect-formatted: \tnotice := Notice(Error("detail"))
// expect-formatted: \texpect_equal(
// expect-formatted: \t\t(notice.failure or panic("called Optional.get() on null")).message,
// expect-formatted: \t\t"detail",
// expect-formatted: \t)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "wrapping evaluates arguments once in written order" {
// expect-formatted: \tvar counter = Counter(0)
// expect-formatted: \texpect_equal(ordered(second: next(counter), first: next(counter)), 21)?
// expect-formatted: \texpect_equal(counter.calls, 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "queue capacity accepts a plain value or omission" {
// expect-formatted: \tvar bounded = Queue[Int](4)
// expect-formatted: \tfor value in [1, 2, 3, 4] {
// expect-formatted: \t\texpect_false(not (bounded.enqueue(value)))?
// expect-formatted: \t}
// expect-formatted: \texpect_false(bounded.enqueue(5))?
// expect-formatted: \texpect_equal(bounded.dequeue() or panic("called Optional.get() on null"), 1)?
// expect-formatted:
// expect-formatted: \tvar unbounded = Queue[Int]()
// expect-formatted: \tvar absent = Queue[Int]()
// expect-formatted: \tcapacity Int? := 4
// expect-formatted: \tvar explicit = Queue[Int](capacity)
// expect-formatted:
// expect-formatted: \tfor value in [1, 2, 3, 4, 5] {
// expect-formatted: \t\texpect_false(not (unbounded.enqueue(value)))?
// expect-formatted: \t\texpect_false(not (absent.enqueue(value)))?
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \texpect_false(not (explicit.enqueue(1)))?
// expect-formatted: }
