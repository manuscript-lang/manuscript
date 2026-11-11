// conform: tags=lists,modules,mutation,optional,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/string-split-replace-join-match-dynamic-calls.ms
import expect_true from "@std/test/test.ms"

test "omitted and supplied caps":
	expect_true(("a,b,c".split(separator: ",").length() == 3))?
	expect_true(("a,b,c".split(separator: ",", max_parts: 2).length() == 2))?
	expect_true(("a,b,c".split(separator: ",", max_parts: none).length() == 3))?
	expect_true(("".split(separator: ",").length() == 1))?
	expect_true(("abc".split(separator: "").length() == 3))?
	expect_true(("a-b-c".replace(old: "-", new: "+") == "a+b+c"))?
	expect_true(("a-b-c".replace_first(old: "-", new: "+") == "a+b-c"))?
	expect_true(("ab".replace(old: "", new: "_") == "_a_b_"))?
	expect_true(("".replace(old: "x", new: "y") == ""))?
	expect_true((["a", "b", "c"].join(separator: "-") == "a-b-c"))?

	none_left: List[String] := []
	expect_true((none_left.join(separator: "-") == ""))?

	var parts = ["x"]
	parts.append(value: "y")
	expect_true((parts.join(separator: "") == "xy"))?
