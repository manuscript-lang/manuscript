// conform: tags=testing,lists,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn ring(slots: List[Int], start: Int, count: Int) Int:
	cap := slots.length()

	if cap == 0 or start < 0:
		return 0

	var total = 0

	for k in 0..count:
		total += slots[(start + k) % cap]

	return total

fn unguarded_ring(slots: List[Int], start: Int) Int:
	cap := slots.length()

	if cap == 0:
		return 0

	return slots[start % cap]

fn dot(a: List[Int], b: List[Int]) Int:
	n := a.length().min(b.length())
	var total = 0

	for i in 0..n:
		total += a[i] * b[i]

	return total

fn scan(values: List[Int]) Int:
	n := values.length()
	var i = 0
	var total = 0

	while i < n and values[i] != 10:
		total += values[i]
		i += 1

	return total

test "a guarded ring index wraps":
	expect_equal(ring([1, 2, 3, 4], 1, 5), 12)?
	expect_equal(ring([1, 2, 3, 4], -1, 5), 0)?
	expect_equal(ring([], 1, 5), 0)?

test "a ring index without a sign guard wraps a positive start":
	expect_equal(unguarded_ring([1, 2, 3], 4), 2)?

test "a dot product stops at the shorter list":
	expect_equal(dot([1, 2, 3, 4], [5, 6]), 17)?
	expect_equal(dot([5, 6], [1, 2, 3, 4]), 17)?

test "a scan stops at a sentinel or the end":
	expect_equal(scan([1, 2, 10, 4]), 3)?
	expect_equal(scan([1, 2]), 3)?

fn largest(values: List[Int]) Int:
	var best = 0

	for i in 1..values.length():
		if values[i].compare(values[best]) > 0:
			best = i

	return values[best]

test "an argmax index stays inside the list":
	expect_equal(largest([3, 9, 2, 9]), 9)?
	expect_equal(largest([7]), 7)?

fn built_then_read(n: Int) Int:
	var values: List[Int] = []

	for i in 0..n:
		values.append(i * 2)

	var total = 0

	for i in 0..n:
		total += values[i]

	return total

fn filtered_then_read(n: Int) Int:
	var values: List[Int] = []

	for i in 0..n:
		if i % 2 == 0:
			values.append(i)

	var total = 0

	for i in 0..values.length():
		total += values[i]

	return total

test "a list built by a counted loop is read by the same count":
	expect_equal(built_then_read(5), 20)?
	expect_equal(built_then_read(0), 0)?

test "a list built by a conditional push is read by its own length":
	expect_equal(filtered_then_read(7), 12)?
