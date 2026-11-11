// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn walked(s: String) List[Int]:
	var out: List[Int] = []
	out.extend(s.scalar_values())
	return out

fn digits_only(s: String) Bool:
	return not s.scalar_values().any(fn c: c < 48 or c > 57)

test "a scalar walk yields what the list holds":
	for s in ["", "abc", "héllo wörld ✓ 😀!", "añb"]:
		listed := s.scalar_values()
		expect_equal(walked(s), listed)?

test "a scalar walk stops at return, break, and continue":
	expect_equal(digits_only("12345"), true)?
	expect_equal(digits_only("12é45"), false)?

	var seen = 0

	for c in "aé😀b".scalar_values():
		if c == 233: continue
		if c == 128512: break

		seen += c

	expect_equal(seen, 97)?

test "a scalar walk reads the text as it was when the loop began":
	var s = "ab"
	var total = 0

	for c in s.clone().scalar_values():
		s = "{s}é"
		total += c

	expect_equal(total, 195)?
	expect_equal(s, "abéé")?
