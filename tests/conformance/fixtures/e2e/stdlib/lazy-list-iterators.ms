// conform: tags=testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `iter` walks a list as borrows; `map` yields one transformed item at a time; `collect` builds the list.

fn scaled_total(xs List[Int], factor Int) Int {
	return xs.iter().seq().map(x => x * factor).fold(0, (total, x) => total + x)
}

test "a mapped walk makes no list until collect" {
	expect_equal(scaled_total([1, 2, 3, 4], 3), 30)?
	expect_equal([1, 2, 3].iter().seq().map(x => x + 1).collect(), [2, 3, 4])?
	expect_equal(List[Int]().iter().seq().count(), 0)?
}

test "mapped items can be strings" {
	words := ["a", "bb", "ccc"]
	expect_equal(words.iter().seq().map(w => w.length()).collect(), [1, 2, 3])?
}
