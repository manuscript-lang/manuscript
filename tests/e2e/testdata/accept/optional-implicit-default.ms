import expect_equal, expect_false from "@std/test/test.ms"

type Config:
	name: String
	limit: Int?

fn find(name: String, limit: Int?, tag: String?) Int:
	if l := limit: return l

	return name.length()

test "defaults":
	c := Config(name: "a")
	try expect_false(c.limit.is_some())
	try expect_equal(find("abc"), 3)
	try expect_equal(find("abc", 7), 7)
	try expect_equal(find("abc", tag: "x"), 3)
