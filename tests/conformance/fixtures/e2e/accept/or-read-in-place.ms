// conform: tags=ownership,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Named {
	name String?
	tags List[String]?
}

fn width(text String?) Int {
	return (text or "none").length()
}

fn same(text String?, other String) Bool {
	return (text or "none") == other
}

fn count(items List[Int]?) Int {
	return (items or [1, 2, 3]).length()
}

fn label(named Named) Int {
	return (named.name or "anonymous").length() + (named.tags or ["a", "b"]).length()
}

test "x or d read in place borrows from x or from the default" {
	expect_equal(width("abc"), 3)?
	expect_equal(width(null), 4)?
	expect_equal(same(null, "none"), true)?
	expect_equal(same("x", "none"), false)?
	expect_equal(count([9]), 1)?
	expect_equal(count(null), 3)?
	expect_equal(label(Named("kim", ["z"])), 4)?
	expect_equal(label(Named(null, null)), 11)?
}
