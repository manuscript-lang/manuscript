// conform: tags=control-flow,lists,loops,stdlib-testing,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn joined_until(stop: String) String:
	words := ["a".clone(), "bb".clone(), "stop".clone(), "ccc".clone()]
	var out = ""
	for w in words:
		if w == stop: break
		out += w
	return out

fn first_long() String:
	words := ["ab".clone(), "abcd".clone(), "abcdef".clone()]
	for w in words:
		if w.length() > 3: return w.clone()
	return ""

fn skipping() Int:
	words := ["a".clone(), "bb".clone(), "c".clone(), "ddd".clone()]
	var n = 0
	for w in words:
		if w.length() < 2: continue
		n += w.length()
	return n

fn nested() Int:
	rows := [["ab".clone(), "stop".clone(), "x".clone()], ["abcd".clone(), "abcdef".clone()], ["z".clone()]]
	var n = 0
	for row in rows:
		for w in row:
			if w == "stop": break
			n += w.length()
		if n > 5: return n
	return n

test "breaking out of a loop over an owned list releases the rest":
	expect_equal(joined_until("stop".clone()), "abb")?

test "returning out of a loop releases the unreached elements":
	expect_equal(first_long(), "abcd")?

test "continue keeps taking elements":
	expect_equal(skipping(), 5)?

test "an inner break and an outer return release both lists":
	expect_equal(nested(), 12)?
