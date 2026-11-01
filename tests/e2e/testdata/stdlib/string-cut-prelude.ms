import expect_equal, expect_some from "@std/test/test.ms"

test "String cut methods work without importing their source module":
    let first = "a=b=c".cut("=") | try expect_some
    try expect_equal(first.before, "a")
    try expect_equal(first.after, "b=c")

    let last = "a=b=c".cut_last("=") | try expect_some
    try expect_equal(last.before, "a=b")
    try expect_equal(last.after, "c")

    let suffix = "prefix".cut_prefix("pre") | try expect_some
    try expect_equal(suffix, "fix")

    let prefix = "prefix".cut_suffix("fix") | try expect_some
    try expect_equal(prefix, "pre")
