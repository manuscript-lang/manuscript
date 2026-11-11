// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Entry:
	name: String
	weight: Int

test "replace returns the old element and stores the new one":
	var names = ["a", "b", "c"]
	expect_equal(names.replace(1, "x"), "b")?
	expect_equal(names.replace(-1, "z"), "c")?
	expect_equal(names, ["a", "x", "z"])?

test "replace moves owned records":
	var entries = [Entry(name: "a", weight: 1), Entry(name: "b", weight: 2)]
	old := entries.replace(0, Entry(name: "c", weight: 3))
	expect_equal(old.name, "a")?
	expect_equal(entries.get(0).name, "c")?
	expect_equal(entries.length(), 2)?

test "replace takes an optional slot":
	var slots: List[String?] = ["a", "b"]
	taken := slots.replace(0, none)
	expect_equal(taken, "a")?
	expect_equal(slots, [none, "b"])?

test "swap exchanges two elements":
	var items = ["a", "b", "c", "d"]
	items.swap(0, 3)
	expect_equal(items, ["d", "b", "c", "a"])?
	items.swap(-2, 1)
	expect_equal(items, ["d", "c", "b", "a"])?
	items.swap(2, 2)
	expect_equal(items, ["d", "c", "b", "a"])?

test "swap moves records without copying":
	var entries = [Entry(name: "a", weight: 1), Entry(name: "b", weight: 2)]
	entries.swap(0, 1)
	expect_equal(entries.get(0).name, "b")?
	expect_equal(entries.get(1).weight, 1)?

test "replace takes a scalar optional slot":
	var slots: List[Int?] = [1, 2]
	expect_equal(slots.replace(1, none), 2)?
	expect_equal(slots, [1, none])?

test "swap exchanges scalars, counting negative indexes from the end":
	var numbers = [1, 2, 3, 4]
	numbers.swap(0, 3)
	expect_equal(numbers, [4, 2, 3, 1])?
	numbers.swap(-3, -2)
	expect_equal(numbers, [4, 3, 2, 1])?
	numbers.swap(1, 1)
	expect_equal(numbers, [4, 3, 2, 1])?

	var flags = [true, false]
	flags.swap(0, -1)
	expect_equal(flags, [false, true])?
