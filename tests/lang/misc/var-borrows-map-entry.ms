// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

test "var of a map entry read changes the entry in place" {
	var m Map[String, List[Int]] = {"a": [1], "b": [9]}
	var entry = m.get("a") or panic("called Optional.get() on null")
	entry.append(2)
	entry.append(3)
	expect_equal(m.get("a") or panic("called Optional.get() on null"), [1, 2, 3])?
	expect_equal(m.get("b") or panic("called Optional.get() on null"), [9])?
}

test "the key variable may change after the entry is borrowed" {
	var m Map[String, List[Int]] = {"a": [1], "b": [9]}
	var key = "a"
	var entry = m.get(key) or panic("called Optional.get() on null")
	key = "b"
	entry.append(2)
	expect_equal(m.get("a") or panic("called Optional.get() on null"), [1, 2])?
	expect_equal(m.get("b") or panic("called Optional.get() on null"), [9])?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
