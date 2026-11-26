// conform: tags=ownership,records
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Src {
	choices List[Int]
}

fn step(move s Src) Src {
	return s
}

fn grow(move s Src, extra Int) Src {
	var next = s.choices.clone()
	next.append(extra)
	return Src(next)
}

// The cell was emptied by the move into `step`, so the assignment has no old record to
// drop.
test "a record moved into a call and reassigned from a bound result, in a loop" {
	var cur = Src([1])
	var rounds = 0

	for round in 0..3 {
		next := step(cur)
		cur = next
		rounds += round
	}

	expect_equal(rounds, 3)?
	expect_equal(cur.choices, [1])?
}

test "a record moved in one branch and reassigned after it" {
	var cur = Src([1])

	for i in 0..4 {
		if i % 2 == 0 {
			next := grow(cur, i)
			cur = next
		} else {
			cur = Src([i])
		}
	}

	expect_equal(cur.choices, [3])?
}

test "a record built from itself still moves its list through" {
	var cur = Src([1])
	for i in 0..3 {
		cur = grow(cur, i)
	}
	expect_equal(cur.choices, [1, 0, 1, 2])?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
