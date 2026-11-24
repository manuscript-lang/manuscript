// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A string built with `+=` of an f-string while a call that can fault is live stays linear: the variable lives in
// a slot, and the append still grows it in place instead of copying it each time.
fn build(n Int) String:
	var b = ""
	for i in 0..n:
		b += f"line {i} and more text\n"
	return b

test "appending an f-string 200000 times grows the string in place":
	s := build(200000)
	expect_equal(s.length(), 5088890)?
	expect_equal(s.starts_with("line 0 and more text\nline 1 "), true)?
