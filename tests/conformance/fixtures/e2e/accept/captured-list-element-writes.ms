// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

fn each(n Int, f fn(Int) Void) Void:
	for i in 0..n:
		f(i)

test "a closure writes elements of a captured list":
	var out List[Int] = [0, 0, 0]
	each(3, r => out[r] = r + 5)
	out | expect_equal([5, 6, 7])?

test "a negative index counts from the end":
	var out List[Int] = [0, 0, 0]
	each(1, r => out[-1] = 9)
	out | expect_equal([0, 0, 9])?

test "droppable elements are replaced and the old ones released":
	var names List[String] = ["a", "b", "c"]
	each(3, r => names[r] = f"n{r}-{names[r]}")
	names | expect_equal(["n0-a", "n1-b", "n2-c"])?

test "elements of a captured list of lists":
	var grid List[List[Int]] = [[1], [2]]
	each(2, r => grid[r] = [r, r + 1])
	grid | expect_equal([[0, 1], [1, 2]])?

test "the closure and its owner share the list":
	var out List[Int] = [0, 0]
	write fn(Int) Void := r => out[r] = 4
	write(1)
	out[0] = 3
	out | expect_equal([3, 4])?

test "an index past the end faults":
	var out List[Int] = [0, 0]
	message := expect_fault(
		fn:
			each(3, r => out[r] = 1)
	)?
	message | expect_contains("index")?
