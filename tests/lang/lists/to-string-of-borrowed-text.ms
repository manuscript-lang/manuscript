// conform: tags=strings,lists,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `to_string` on a loop element that borrows its text gives an owned copy a list can keep.
fn pass(s String) String {
	return s.to_string()
}

test "to_string of a borrowed String is an owned String" {
	var cs List[String] = []
	for ch in "abc".chars() { cs.append(ch.to_string()) }
	expect_equal(cs.join(""), "abc")?

	var seen = ""

	for ch in "xy".chars() {
		x := ch.to_string()
		seen += x + pass(ch) + ch
	}

	expect_equal(seen, "xxxyyy")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
