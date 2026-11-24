// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A list built with a length the checker cannot see: the first access at an index
// checks it, and a later access at the same index, even on the updated list, needs no
// check of its own.
fn filled(n Int) Int {
	var xs = [0].repeated(n)
	var total = 0

	for i in 0..n {
		xs[i] = i * 2
		total += xs[i] + xs[i]
	}

	return total
}

fn after_clone(n Int) Int {
	var xs = [1].repeated(n)
	var ys = xs.clone()
	var total = 0

	for i in 0..n {
		ys[i] = xs[i] + i
		total += ys[i]
	}

	return total
}

test "an access that has run guards a later access at the same index" {
	filled(5) | expect_equal(40)?
	filled(0) | expect_equal(0)?
	after_clone(4) | expect_equal(10)?
}
