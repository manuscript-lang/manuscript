import (
	choice, sample, secure_int, seeded, shuffle, weighted_choice from "@std/random.ms",
	expect_equal,
	expect_error,
	expect_fault,
	expect_none,
	expect_ok,
	expect_some,
	expect_true from "@std/test/test.ms",
)

test "seeded sample picks distinct items":
	var rng = seeded(7)
	picked := rng.sample([10, 20, 30, 40, 50], 3)
	expect_equal(picked.length(), 3)?
	expect_equal(picked.sorted().length(), 3)?
	for item in picked:
		expect_true(item % 10 == 0 and item >= 10 and item <= 50)?
	expect_equal(
		picked[0] == picked[1] or picked[1] == picked[2] or picked[0] == picked[
			2
		],
		false,
	)?

	var again = seeded(7)
	expect_equal(again.sample([10, 20, 30, 40, 50], 3), picked)?
	expect_equal(rng.sample([1, 2], 0), List[Int]())?
	expect_equal(rng.sample([1, 2, 3], 3).sorted(), [1, 2, 3])?

test "seeded weighted_choice follows the weights":
	var rng = seeded(3)
	for round in 0..50:
		expect_equal(
			expect_some(
				rng.weighted_choice(["a", "b", "c"], [0.0, 1.0, 0.0])
			)?,
			"b",
		)?
	expect_none(rng.weighted_choice(List[String](), List[Float]()))?

	var heavy = 0
	for draw in 0..200:
		if expect_some(rng.weighted_choice(["x", "y"], [9.0, 1.0]))? == "x":
			heavy += 1
	expect_true(heavy > 140)?

fn discard[T](value: T) Unit:
	return unit

test "seeded invalid arguments fault":
	var rng = seeded(1)
	_first := expect_fault(fn: discard(rng.sample([1], 2)))?
	_second := expect_fault(fn: discard(rng.weighted_choice([1, 2], [1.0])))?
	_third := expect_fault(fn: discard(rng.weighted_choice([1, 2], [0.0, 0.0])))?
	_fourth := expect_fault(fn: discard(rng.weighted_choice([1, 2], [-1.0, 2.0])))?

test "secure sample and weighted_choice":
	picked := expect_ok(sample([1, 2, 3, 4], 4))?
	expect_equal(picked.sorted(), [1, 2, 3, 4])?
	expect_equal(expect_ok(sample([1, 2, 3], 0))?, List[Int]())?

	_error := expect_error(sample([1], 2))?
	expect_equal(expect_some(expect_ok(weighted_choice(["a", "b"], [0.0, 2.0]))?)?, "b")?

	_other := expect_error(weighted_choice(["a"], [0.0]))?
	expect_none(expect_ok(weighted_choice(List[String](), List[Float]()))?)?

test "secure_int covers wide and empty ranges":
	_same := expect_error(secure_int(3, 3))?
	_reversed := expect_error(secure_int(5, 2))?
	expect_equal(secure_int(7, 8)?, 7)?

	wide := secure_int(-9223372036854775807 - 1, none)?
	expect_true(wide <= 9223372036854775806)?

	low := secure_int(-9223372036854775807 - 1, -9223372036854775807)?
	expect_equal(low, -9223372036854775807 - 1)?

	empty: List[Int] := []
	expect_equal(choice(empty)?, none)?
	expect_equal(shuffle([5])?, [5])?

fn draw_wide(min: Int, max_exclusive: Int) Unit:
	var rng = seeded(1)
	discard(rng.int(min, max_exclusive))

test "seeded int names a range wider than the largest Int":
	message := expect_fault(fn: draw_wide(-9223372036854775807, 9223372036854775807))?
	expect_true(message.contains("wider than the largest Int"))?

	edge := expect_fault(fn: draw_wide(-1, 9223372036854775807))?
	expect_true(edge.contains("wider than the largest Int"))?

	var rng = seeded(1)
	widest := rng.int(-1, 9223372036854775806)
	expect_true(widest >= -1 and widest < 9223372036854775806)?
