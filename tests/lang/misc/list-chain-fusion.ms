// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn chain(xs List[Int], k Int) Int {
	return xs.map(x => x * k).filter(x => x % 3 == 0).map(x => x + 1).sum()
}

fn counted(n Int) Int {
	var total = 0
	for r in 0..n {
		total += (0..r).map(x => x * 2).filter(x => x % 4 == 0).length()
	}
	return total
}

test "a map, filter and sum chain gives the staged answer" {
	expect_equal(chain([1, 2, 3, 4, 5, 6], 3), 69)?
}

test "an empty source and a filter that keeps nothing give zero" {
	expect_equal(chain([], 7), 0)?
	expect_equal(chain([1, 2, 4], 1), 0)?
}

test "a chain inside a loop builds each pass from nothing" {
	expect_equal(counted(6), 9)?
}
