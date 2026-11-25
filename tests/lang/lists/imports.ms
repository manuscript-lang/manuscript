// conform: tags=formatter,lists,maps,modules,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/imports.ms
import expect_equal from "@std/test/test.ms"

test "grouped imports" {
	values List[Int] := [1, 2]
	var entries = Map[String, Int]()
	entries.add("count", values.length())
	expect_equal(entries.length(), 1)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
