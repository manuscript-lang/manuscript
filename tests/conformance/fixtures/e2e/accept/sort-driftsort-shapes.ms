// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_fault from "@std/test/test.ms"

type Plain:
	key: Int
	id: Int

type Entry:
	key: Int
	id: Int
	name: String

// Keys of one input shape: sorted and reversed runs, ties, a pipe organ, a sawtooth, a
// sorted prefix with a random tail, and plain random keys of a few sizes.
fn keys(shape: Int, count: Int) List[Int]:
	var out: List[Int] = []
	var x = 12345

	for i in 0..count:
		x = (x * 1103515245 + 12345) % 2147483648

		var key = x % 1000000

		if shape == 0:
			key = i
		else if shape == 1:
			key = count - i
		else if shape == 2:
			key = 5
		else if shape == 3:
			key = count - i
			if i < count / 2:
				key = i
		else if shape == 4:
			key = i % 37
		else if shape == 5 and i < count - count / 20:
			key = i
		else if shape == 6:
			key = x % 4
		else if shape == 7:
			key = x % 300
		else if shape == 8:
			key = i / 3 + x % 2
		else if shape == 9:
			key = 100000 - i
			if i % 200 < 100:
				key = i

		out.append(key)

	return out

fn plains(shape: Int, count: Int) List[Plain]:
	var out: List[Plain] = []
	for key in keys(shape, count):
		out.append(Plain(key: key, id: out.length()))
	return out

fn entries(shape: Int, count: Int) List[Entry]:
	var out: List[Entry] = []
	for key in keys(shape, count):
		out.append(
			Entry(
				key: key,
				id: out.length(),
				name: "entry-name-longer-than-inline-{key}",
			)
		)
	return out

fn plain_ok(list: List[Plain], count: Int) Bool:
	if list.length() != count: return false

	var seen = 0

	for i in 0..count:
		seen += list[i].id

		if i > 0:
			before := list[i - 1]
			after := list[i]
			if (
				before.key > after.key
				or (before.key == after.key and before.id > after.id)
			):
				return false

	return seen == count * (count - 1) / 2

fn entry_ok(list: List[Entry], count: Int) Bool:
	if list.length() != count: return false

	var seen = 0

	for i in 0..count:
		e := list[i]
		seen += e.id
		if e.name != "entry-name-longer-than-inline-{e.key}": return false

		if i > 0:
			before := list[i - 1]
			if before.key > e.key or (before.key == e.key and before.id > e.id):
				return false

	return seen == count * (count - 1) / 2

test "plain records of every shape sort stably at sizes around the small-sort and run thresholds":
	for count in [
		0, 1, 2, 3, 19, 20, 21, 22, 40, 63, 64, 65, 100, 129, 1000, 5000, 20000
	]:
		for shape in 0..10:
			sorted := plains(shape, count).sorted(
				compare: fn(a: Plain, b: Plain) Int: (a.key - b.key)
			)
			expect_equal(plain_ok(sorted, count), true)?

test "records that own strings of every shape sort stably, sorted and in place":
	for count in [0, 1, 21, 64, 65, 300, 5000, 20000]:
		for shape in 0..10:
			original := entries(shape, count)
			sorted := original.sorted(
				compare: fn(a: Entry, b: Entry) Int: a.key - b.key
			)
			expect_equal(entry_ok(sorted, count), true)?
			expect_equal(original.length(), count)?

			var list = entries(shape, count)
			list.sort(compare: fn(a: Entry, b: Entry) Int: a.key - b.key)
			expect_equal(entry_ok(list, count), true)?

test "a descending comparator sorts ties in input order":
	sorted := plains(7, 20000).sorted(
		compare: fn(a: Plain, b: Plain) Int: b.key - a.key
	)
	var ok = true

	for i in 1..sorted.length():
		before := sorted[i - 1]
		after := sorted[i]
		if before.key < after.key or (before.key == after.key and before.id > after.id):
			ok = false

	expect_equal(ok, true)?

fn faulting(a: Entry, b: Entry) Int:
	if a.id == 777 and b.id != 777: return 1 / (a.id - 777)
	return a.key - b.key

test "a comparator that faults mid-sort leaves the original list whole":
	original := entries(7, 5000)
	message := expect_fault(
		fn() Unit:
			original.sorted(compare: faulting)
	)?
	expect_equal(message.length() > 0, true)?

	var ids = 0

	for e in original:
		ids += e.id
		if e.name != "entry-name-longer-than-inline-{e.key}":
			ids = -1

	expect_equal(ids, 5000 * 4999 / 2)?
