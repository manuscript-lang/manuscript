// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

// `pop` runs in line: the last element moves out, an empty list answers none, and a list
// held in a field or inside another list changes in place.
type Bag:
	items List[String]

fn var Bag.take_last() String?:
	return self.items.pop()

test "pop moves scalars out until the list is empty":
	var xs = [1, 2, 3]
	expect_equal(xs.pop() or 0, 3)?
	expect_equal(xs.pop() or 0, 2)?
	expect_equal(xs.length(), 1)?
	expect_equal(xs.pop() or 0, 1)?
	expect_true(xs.pop() == null)?
	expect_equal(xs.length(), 0)?

test "pop moves owned elements without copying them":
	var names = ["a", "bb", "ccc"]
	expect_equal(names.pop() or "", "ccc")?
	expect_equal(names.length(), 2)?

test "pop changes a list held in a field or an element":
	var bag = Bag(items: ["u", "vv"])
	expect_equal(bag.take_last() or "", "vv")?
	expect_equal(bag.items.length(), 1)?

	var rows = [["p"], ["q", "r"]]
	expect_equal(rows[1].pop() or "", "r")?
	expect_equal(rows[1].pop() or "", "q")?
	expect_true(rows[1].pop() == null)?
	expect_equal(rows[0].length(), 1)?
