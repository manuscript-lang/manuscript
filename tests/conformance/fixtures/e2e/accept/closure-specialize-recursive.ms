// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A recursive function that passes its closure parameter on gets a private copy for a known closure.
fn count_matches(items List[Int], lo Int, hi Int, keep fn(Int) Bool) Int:
	if hi - lo == 0: return 0
	if hi - lo == 1:
		if keep(items.get(lo)): return 1
		return 0
	mid := lo + (hi - lo) / 2
	return count_matches(items, lo, mid, keep) + count_matches(items, mid, hi, keep)

test "a recursive helper called with a known closure":
	items := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	expect_equal(count_matches(items, 0, items.length(), x => x % 2 == 0), 5)?
	limit := 6
	expect_equal(count_matches(items, 0, items.length(), x => x > limit), 4)?
