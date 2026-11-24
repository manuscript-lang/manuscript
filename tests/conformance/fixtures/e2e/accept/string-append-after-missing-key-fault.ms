// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// The fault text of a missing map key is built with the same concat as `s += c`; declaring it first must not hide
// the append from the in-place growth, or this loop copies the whole string on every step and runs for minutes.
fn lookup(m Map[String, Int], key String) Int:
	return m[key]

fn grow(n Int) String:
	var s = ""
	for i in 0..n:
		s += "x"
	return s

test "an append loop grows in place":
	var m = Map[String, Int]()
	m["a"] = 1
	expect_equal(lookup(m, "a"), 1)?
	expect_equal(grow(1000000).length(), 1000000)?
