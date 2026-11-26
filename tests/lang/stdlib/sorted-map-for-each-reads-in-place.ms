// conform: tags=maps,stdlib-collections,tier-stdlib
// conform: phase=test
import SortedMap from "@std/collections/sorted.ms"
import expect_equal from "@std/test/test.ms"
import compile, Regex from "@std/regex.ms"

type Rule {
	re Regex
}

test "for_each visits entries in key order without copying them" {
	var m = SortedMap[String, Int]()
	m.add("b", 2)
	m.add("a", 1)
	m.add("c", 3)
	var seen = ""
	m.for_each((k, v) => seen += f"{k}{v}")
	expect_equal(seen, "a1b2c3")?
}

test "for_each works for values that cannot be copied" {
	var m = SortedMap[String, Rule]()
	m.add("x", Rule(compile("x+").get()))
	var hits = 0
	m.for_each((k, r) => hits += if r.re.matches("xx") { 1 } else { 0 })
	expect_equal(hits, 1)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
