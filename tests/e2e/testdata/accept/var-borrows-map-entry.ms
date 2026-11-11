import expect_equal from "@std/test/test.ms"

test "var of a map entry read changes the entry in place":
	var m: Map[String, List[Int]] = {"a": [1], "b": [9]}
	var entry = m.get("a").get()
	entry.append(2)
	entry.append(3)
	expect_equal(m.get("a").get(), [1, 2, 3])?
	expect_equal(m.get("b").get(), [9])?

test "the key variable may change after the entry is borrowed":
	var m: Map[String, List[Int]] = {"a": [1], "b": [9]}
	var key = "a"
	var entry = m.get(key).get()
	key = "b"
	entry.append(2)
	expect_equal(m.get("a").get(), [1, 2])?
	expect_equal(m.get("b").get(), [9])?
