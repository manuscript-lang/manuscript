// conform: tags=closures,control-flow,lists,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn neighbours(n: Int) Int:
	var total = 0
	for i in 0..n:
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			total += (d[0] + 2) * (d[1] + 3) * i
	return total

fn first_hit(limit: Int) Int:
	var i = 0
	while i < limit:
		for step in [3, 5, 7]:
			if (i * step) % 11 == 10: return i * 100 + step
		i += 1
	return -1

fn breaks_and_continues() Int:
	var seen = 0
	for i in 0..4:
		for d in [[0, 1], [1, 1], [2, 1]]:
			if d[0] == 1: continue
			if i == 3: break
			seen += d[0] + d[1] + i
	return seen

fn floats(n: Int) Float:
	var t = 0.0
	for i in 0..n:
		for w in [0.5, 1.5]:
			t += w
	return t

fn mutated_copy(n: Int) Int:
	var kept = 0
	for i in 0..n:
		for d in [[1, 2], [3, 4]]:
			var copy = d.clone()
			copy.append(i)
			kept += copy.length() + d.length()
	return kept

fn escapes(n: Int) List[List[Int]]:
	var out: List[List[Int]] = []
	for i in 0..n:
		for d in [[1, 2], [3, 4]]:
			out.append(d)
	return out

test "a table iterated in a loop gives the same results as building it each time":
	expect_equal(neighbours(5), 240)?
	expect_equal(neighbours(0), 0)?
	expect_equal(first_hit(50), 205)?
	expect_equal(first_hit(1), -1)?
	expect_equal(breaks_and_continues(), 18)?
	expect_equal(floats(4), 8.0)?

test "a loop variable that changes or escapes owns its list":
	expect_equal(mutated_copy(3), 30)?
	expect_equal(escapes(2), [[1, 2], [3, 4], [1, 2], [3, 4]])?
	closure_total := [1, 2, 3].map(fn x: x + 1).filter(fn x: x > 0).sum()
	expect_equal(closure_total, 9)?
