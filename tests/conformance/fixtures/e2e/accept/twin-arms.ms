// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Two arms that run the same checked stores on different operands.
fn merge_sorted(left List[Int], right List[Int]) List[Int]:
	var out = [0].repeated(left.length() + right.length())
	var i = 0
	var j = 0
	var k = 0
	while i < left.length() and j < right.length():
		if right.get(j) < left.get(i):
			out.set(k, right.get(j))
			j += 1
		else:
			out.set(k, left.get(i))
			i += 1
		k += 1
	while i < left.length():
		out.set(k, left.get(i))
		i += 1
		k += 1
	while j < right.length():
		out.set(k, right.get(j))
		j += 1
		k += 1
	return out

// Arms that own different strings stay separate branches.
fn pick(flag Bool, a String, b String) String:
	if flag:
		return a + "!"
	else:
		return b + "?"

// Arms that differ in a constant and in a value computed from the operands.
fn clamp_count(x Int, limit Int) Int:
	var count = 0
	if x > limit:
		count = count + limit + 1
	else:
		count = count + x + 2
	return count

test "a merge of two sorted lists keeps order and ties":
	expect_equal(merge_sorted([1, 3, 5, 7], [2, 3, 6]), [1, 2, 3, 3, 5, 6, 7])?
	expect_equal(merge_sorted([], [4, 5]), [4, 5])?
	expect_equal(merge_sorted([9], []), [9])?

test "arms that own different strings pick the right one":
	expect_equal(pick(true, "a", "b"), "a!")?
	expect_equal(pick(false, "a", "b"), "b?")?

test "arms that differ in constants compute each path":
	expect_equal(clamp_count(10, 3), 4)?
	expect_equal(clamp_count(1, 3), 3)?
