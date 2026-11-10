import expect_equal, expect_some from "@std/test/test.ms"

test "String affix methods work without importing their source module":
	suffix := "prefix".cut_prefix("pre") | try expect_some
	try expect_equal(suffix, "fix")

	prefix := "prefix".cut_suffix("fix") | try expect_some
	try expect_equal(prefix, "pre")
