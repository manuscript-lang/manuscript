import expect_equal, expect_some from "@std/test/test.ms"

test "String affix methods work without importing their source module":
    let suffix = "prefix".cut_prefix("pre") | try expect_some
    try expect_equal(suffix, "fix")

    let prefix = "prefix".cut_suffix("fix") | try expect_some
    try expect_equal(prefix, "pre")
