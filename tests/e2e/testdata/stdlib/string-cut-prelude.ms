import expect_equal, expect_some from "@std/test/test.ms"

test "String affix methods work without importing their source module":
	suffix := "prefix".cut_prefix("pre") | expect_some?
	expect_equal(suffix, "fix")?

	prefix := "prefix".cut_suffix("fix") | expect_some?
	expect_equal(prefix, "pre")?
