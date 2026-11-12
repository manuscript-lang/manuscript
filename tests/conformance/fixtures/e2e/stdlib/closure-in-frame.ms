// conform: tags=closures,strings,lists,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn apply(f: fn(Int) Int, n: Int) Int:
	var acc = 0
	for i in 0..n:
		acc += f(i)
	return acc

fn keep(f: fn(Int) Int) fn(Int) Int:
	return f

test "a closure passed only to calls is released with its captures":
	label := "a-label-longer-than-twenty-two-bytes"
	items := [1, 2, 3]
	var total = 0
	for r in 0..50:
		total += apply(fn i: label.length() + items[i % 3] + r, 4)
	expect_equal(total, 12450)?

test "a closure that outlives the frame owns its captures":
	label := "another-label-longer-than-twenty-two"
	kept := keep(fn i: label.length() + i)
	expect_equal(kept(1), 37)?
	expect_equal(apply(kept, 3), 3 * 36 + 3)?
