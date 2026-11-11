// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

// Lowering moves or lends a value with one owner where the program wrote no `.clone()`:
// `pop` takes the element out of the list, `get` on an owned optional or result hands the
// payload over and on a borrowed one lends it, a native lend such as `get(i)` is a
// lending result, and a function value with defaults passes a supplied argument
// through.
// `make copy-check` sweeps this fixture for implicit copies.

type Counter:
	values: List[Int]

fn Counter.read() Int:
	return self.values[0]

fn counter(n: Int) Counter:
	return Counter(values: [n])

type Ring:
	slots: List[Counter?]
	size: Int

fn Ring.at(index: Int) Counter?:
	if index < 0 or index >= self.size: return none
	return self.slots.get(index)

fn maybe(n: Int) Counter?:
	if n < 0: return none
	return counter(n)

fn make(n: Int) Counter!:
	if n < 0: return error(Error("negative"))
	return ok(counter(n))

fn total(counters: List[Counter], scale: Int = 1) Int:
	var sum = 0
	for c in counters: sum += c.read() * scale
	return sum

test "pop moves the element out of the list":
	var counters = [counter(1), counter(2), counter(3)]
	var seen: List[Int] = []
	while not counters.is_empty():
		if c := counters.pop(): seen.append(c.read())
	seen | expect_equal([3, 2, 1])?
	counters.length() | expect_equal(0)?

test "get on an owned optional hands the payload over":
	taken := maybe(6).get()
	taken.read() | expect_equal(6)?

	later := maybe(9).get()
	later.read() | expect_equal(9)?

test "get on a borrowed result lends the payload":
	r := make(7)
	(not r.is_error() and r.get().read() == 7) | expect_true?
	r.get().read() | expect_equal(7)?

test "a native lend beside a none path still lends":
	slots: List[Counter?] := [counter(8), none]
	ring := Ring(slots: slots, size: 2)
	if c := ring.at(0): c.read() | expect_equal(8)?
	ring.at(1).is_none() | expect_true?
	ring.at(5).is_none() | expect_true?

test "a function value with defaults passes a supplied argument through":
	alias := total
	counters := [counter(1), counter(2)]
	alias(counters) | expect_equal(3)?
	alias(counters, 10) | expect_equal(30)?
	counters.length() | expect_equal(2)?
